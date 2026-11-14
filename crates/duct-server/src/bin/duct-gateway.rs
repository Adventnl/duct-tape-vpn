use axum::{
    Router,
    body::{Body, to_bytes},
    extract::{DefaultBodyLimit, Request, State},
    http::{StatusCode, header},
    response::Response,
    routing::post,
};
use clap::Parser;
use std::{path::PathBuf, sync::Arc, time::Duration};
#[derive(Parser)]
struct Args {
    #[arg(long)]
    socket: PathBuf,
    #[arg(long, default_value = "127.0.0.1:8787")]
    listen: std::net::SocketAddr,
}
struct Proxy {
    client: reqwest::Client,
    permits: tokio::sync::Semaphore,
}
async fn forward(State(proxy): State<Arc<Proxy>>, req: Request) -> Result<Response, StatusCode> {
    let _permit = proxy
        .permits
        .try_acquire()
        .map_err(|_| StatusCode::TOO_MANY_REQUESTS)?;
    let path = req.uri().path().to_string();
    let bytes = to_bytes(req.into_body(), 8192)
        .await
        .map_err(|_| StatusCode::PAYLOAD_TOO_LARGE)?;
    let response = proxy
        .client
        .post(format!("http://localhost{path}"))
        .header(header::CONTENT_TYPE, "application/json")
        .body(bytes)
        .send()
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    let status = response.status();
    let body = response
        .bytes()
        .await
        .map_err(|_| StatusCode::BAD_GATEWAY)?;
    if body.len() > 65536 {
        return Err(StatusCode::BAD_GATEWAY);
    };
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::from(body))
        .map_err(|_| StatusCode::BAD_GATEWAY)
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();
    anyhow::ensure!(
        args.listen.ip().is_loopback(),
        "gateway must sit behind the inspected TLS ingress on loopback"
    );
    let proxy = Arc::new(Proxy {
        client: reqwest::Client::builder()
            .unix_socket(args.socket)
            .timeout(Duration::from_secs(8))
            .redirect(reqwest::redirect::Policy::none())
            .build()?,
        permits: tokio::sync::Semaphore::new(32),
    });
    let app = Router::new()
        .route("/v1/activate", post(forward))
        .route("/v1/challenge", post(forward))
        .route("/v1/claim", post(forward))
        .route("/v1/poll", post(forward))
        .layer(DefaultBodyLimit::max(8192))
        .with_state(proxy);
    axum::serve(tokio::net::TcpListener::bind(args.listen).await?, app).await?;
    Ok(())
}
