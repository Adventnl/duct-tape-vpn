//! Stages a TUF-verified artifact. Never installs, restarts a service, or publishes.
use anyhow::{Context, Result, ensure};
use clap::Parser;
use duct_core::{
    crypto,
    protocol::{Signed, bytes},
};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tough::{IntoVec, RepositoryLoader, TargetName};
#[derive(Parser)]
struct Args {
    #[arg(long)]
    root: PathBuf,
    #[arg(long)]
    metadata_url: String,
    #[arg(long)]
    targets_url: String,
    #[arg(long)]
    cache: PathBuf,
    #[arg(long)]
    approval: PathBuf,
    #[arg(long)]
    server_key: String,
    #[arg(long)]
    platform: String,
    #[arg(long)]
    current_version: u64,
    #[arg(long)]
    output: PathBuf,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    version: u64,
    platform: String,
    protocol_min: u32,
    protocol_max: u32,
    artifact: String,
    sha256: String,
    length: u64,
}
#[tokio::main]
async fn main() -> Result<()> {
    let a = Args::parse();
    ensure!(!a.output.exists(), "output already exists");
    let meta = reqwest::Url::parse(&a.metadata_url)?;
    let targets = reqwest::Url::parse(&a.targets_url)?;
    ensure!(
        meta.scheme() == "https" && targets.scheme() == "https",
        "HTTPS required"
    );
    std::fs::create_dir_all(&a.cache)?;
    let root = std::fs::read(a.root)?;
    // Persistent tough datastore enforces metadata rollback and trusted root rotation; expiry checks stay enabled.
    let repo = RepositoryLoader::new(&root, meta, targets)
        .datastore(&a.cache)
        .load()
        .await?;
    let manifest_name = TargetName::new(format!("{}.manifest.json", a.platform))?;
    ensure!(
        repo.targets()
            .signed
            .targets_map()
            .get(&manifest_name)
            .context("manifest missing")?
            .length
            <= 16384,
        "oversized manifest metadata"
    );
    let manifest_bytes = repo
        .read_target(&manifest_name)
        .await?
        .context("manifest missing")?
        .into_vec()
        .await?;
    ensure!(manifest_bytes.len() <= 16384, "oversized manifest");
    let m: Manifest = serde_json::from_slice(&manifest_bytes)?;
    ensure!(
        m.platform == a.platform
            && m.protocol_min <= 1
            && m.protocol_max >= 1
            && m.version > a.current_version,
        "incompatible or rollback release"
    );
    let approval: Signed<serde_json::Value> = serde_json::from_slice(&std::fs::read(a.approval)?)?;
    crypto::verify(
        &a.server_key,
        &bytes("admin-result", &approval.payload)?,
        &approval.signature,
    )?;
    ensure!(
        approval.payload["result"]["approved_release"].as_u64() == Some(m.version)
            && approval.payload["result"]["sha256"].as_str() == Some(&m.sha256),
        "Owner release approval required"
    );
    ensure!(
        m.length > 0 && m.length <= 512 * 1024 * 1024,
        "invalid artifact length"
    );
    // Do not use target bytes until the entire TUF stream has passed its length and hash verification.
    let artifact_name = TargetName::new(m.artifact)?;
    ensure!(
        repo.targets()
            .signed
            .targets_map()
            .get(&artifact_name)
            .context("artifact metadata missing")?
            .length
            == m.length,
        "artifact metadata length mismatch"
    );
    let artifact = repo
        .read_target(&artifact_name)
        .await?
        .context("artifact missing")?
        .into_vec()
        .await?;
    use sha2::{Digest, Sha256};
    let hash = format!("{:x}", Sha256::digest(&artifact));
    ensure!(
        hash == m.sha256 && artifact.len() as u64 == m.length,
        "artifact manifest mismatch"
    );
    duct_server::create_private(&a.output, &artifact)?;
    println!(
        "Verified and staged version {}. Installation requires a separate platform action; server deployment requires separate approval.",
        m.version
    );
    Ok(())
}
