use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
};
use clap::Parser;
use duct_core::{protocol::*, registry::Registry};
use duct_server::{App, now};
use std::{path::PathBuf, time::Duration};
#[derive(Parser)]
struct Args {
    #[arg(long)]
    config: PathBuf,
}
struct Error;
impl IntoResponse for Error {
    fn into_response(self) -> Response {
        (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error":"request rejected"})),
        )
            .into_response()
    }
}
async fn execute<T: serde::Serialize + Send + 'static>(
    app: App,
    op: impl FnOnce(&mut Registry) -> anyhow::Result<T> + Send + 'static,
) -> Result<Json<T>, Error> {
    tokio::task::spawn_blocking(move || {
        let mut registry = app.registry.lock().map_err(|_| Error)?;
        op(&mut registry).map(Json).map_err(|_| Error)
    })
    .await
    .map_err(|_| Error)?
}
async fn challenge(
    State(app): State<App>,
    Json(req): Json<Enrollment>,
) -> Result<Json<Signed<Challenge>>, Error> {
    execute(app, move |r| r.challenge(req, now())).await
}
async fn claim(
    State(app): State<App>,
    Json(req): Json<Claim>,
) -> Result<Json<Signed<serde_json::Value>>, Error> {
    execute(app, move |r| r.claim(req, now())).await
}
async fn poll(
    State(app): State<App>,
    Json(req): Json<Poll>,
) -> Result<Json<Signed<serde_json::Value>>, Error> {
    execute(app, move |r| r.poll(req, now())).await
}
async fn admin(
    State(app): State<App>,
    Json(req): Json<Signed<AdminRequest>>,
) -> Result<Json<Signed<serde_json::Value>>, Error> {
    execute(app, move |r| r.admin(req, now())).await
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    duct_server::init_logs();
    let config = duct_server::read_config(&Args::parse().config)?;
    let app = App::open(config.database, config.identity)?;
    let public = Router::new()
        .route("/v1/challenge", post(challenge))
        .route("/v1/claim", post(claim))
        .route("/v1/poll", post(poll))
        .layer(DefaultBodyLimit::max(8192))
        .with_state(app.clone());
    let admin = Router::new()
        .route("/v1/admin", post(admin))
        .layer(DefaultBodyLimit::max(8192))
        .with_state(app.clone());
    let public_listener = duct_server::unix_listener(&config.public_socket).await?;
    let admin_listener = duct_server::unix_listener(&config.admin_socket).await?;
    let helper_socket = config.helper_socket.clone();
    tokio::spawn(async move {
        loop {
            let result: anyhow::Result<()> = async {
                let desired = app
                    .registry
                    .lock()
                    .map_err(|_| anyhow::anyhow!("registry lock"))?
                    .desired_peers()?;
                let client = reqwest::Client::builder()
                    .unix_socket(helper_socket.clone())
                    .timeout(Duration::from_secs(5))
                    .build()?;
                client
                    .post("http://localhost/reconcile")
                    .json(&desired)
                    .send()
                    .await?
                    .error_for_status()?;
                app.registry
                    .lock()
                    .map_err(|_| anyhow::anyhow!("registry lock"))?
                    .mark_applied(desired.revision)?;
                Ok(())
            }
            .await;
            if result.is_err() {
                tracing::warn!(event = "reconcile_failed");
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        }
    });
    tokio::try_join!(
        axum::serve(public_listener, public),
        axum::serve(admin_listener, admin)
    )?;
    Ok(())
}
