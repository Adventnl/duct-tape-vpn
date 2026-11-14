use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, State},
    http::StatusCode,
    routing::post,
};
use clap::Parser;
use duct_core::helper::PeerSet;
use std::{path::PathBuf, sync::Arc};
use tokio::{process::Command, sync::Mutex};
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
    peers.validate().map_err(|_| StatusCode::BAD_REQUEST)?;
    let current = tokio::time::timeout(
        std::time::Duration::from_secs(2),
        Command::new("/usr/bin/wg")
            .args(["show", "dtvpn0", "peers"])
            .kill_on_drop(true)
            .output(),
    )
    .await
    .map_err(|_| StatusCode::GATEWAY_TIMEOUT)?
    .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
    if !current.status.success() {
        return Err(StatusCode::SERVICE_UNAVAILABLE);
    }
    let existing = std::str::from_utf8(&current.stdout)
        .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?
        .split_whitespace()
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let args = peers
        .set_args(&existing)
        .map_err(|_| StatusCode::BAD_REQUEST)?;
    if args.is_empty() {
        return Ok(StatusCode::NO_CONTENT);
    }
    // syncconf treats omitted interface fields as zero: a peer-only config clears
    // the private key, randomizes ListenPort and resets FwMark on every update.
    // wg set changes only these validated peers, preserving interface identity,
    // port, routing mark and each retained peer's endpoint/keepalive/PSK.
    // No shell, no user-selected interface, path, command or AllowedIPs. Only the owned interface.
    let mut child = Command::new("/usr/bin/wg")
        .args(["set", "dtvpn0"])
        .args(args)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .kill_on_drop(true)
        .spawn()
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
