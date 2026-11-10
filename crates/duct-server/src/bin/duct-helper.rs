use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    routing::post,
};
use clap::Parser;
use duct_core::helper::PeerSet;
use std::{path::PathBuf, sync::Arc};
use tokio::{io::AsyncWriteExt, process::Command, sync::Mutex};
#[derive(Parser)]
struct Args {
    #[arg(long)]
    socket: PathBuf,
}
async fn reconcile(
    State(lock): State<Arc<Mutex<()>>>,
    Json(peers): Json<PeerSet>,
) -> Result<StatusCode, StatusCode> {
    let _lock = lock.lock().await;
    let conf = peers.syncconf().map_err(|_| StatusCode::BAD_REQUEST)?;
    // No shell, no user-selected interface, path, command or AllowedIPs. Only the owned interface.
    let mut child = Command::new("/usr/bin/wg")
        .args(["syncconf", "dtvpn0", "/dev/stdin"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    child
        .stdin
        .take()
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?
        .write_all(conf.as_bytes())
        .await
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    let status = tokio::time::timeout(std::time::Duration::from_secs(4), child.wait())
        .await
        .map_err(|_| StatusCode::GATEWAY_TIMEOUT)?
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    if status.success() {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(StatusCode::SERVICE_UNAVAILABLE)
    }
}
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let listener = duct_server::unix_listener(&Args::parse().socket).await?;
    let app = Router::new()
        .route("/reconcile", post(reconcile))
        .layer(DefaultBodyLimit::max(65536))
        .with_state(Arc::new(Mutex::new(())));
    axum::serve(listener, app).await?;
    Ok(())
}
