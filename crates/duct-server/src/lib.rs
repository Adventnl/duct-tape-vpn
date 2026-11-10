use anyhow::{Result, ensure};
use duct_core::{crypto, registry::Registry};
use p256::ecdsa::SigningKey;
use serde::Deserialize;
use std::{
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_secs() as i64
}
pub fn load_key(path: &Path) -> Result<SigningKey> {
    let key = zeroize::Zeroizing::new(std::fs::read(path)?);
    Ok(SigningKey::from_slice(&key)?)
}
pub fn create_private(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::{io::Write, os::unix::fs::OpenOptionsExt};
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    Ok(())
}
#[derive(Clone)]
pub struct App {
    pub registry: Arc<Mutex<Registry>>,
}
impl App {
    pub fn open(db: PathBuf, key: PathBuf) -> Result<Self> {
        let registry = Registry::open(db, load_key(&key)?)?;
        registry.check()?;
        Ok(Self {
            registry: Arc::new(Mutex::new(registry)),
        })
    }
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub database: PathBuf,
    pub identity: PathBuf,
    pub public_socket: PathBuf,
    pub admin_socket: PathBuf,
    pub helper_socket: PathBuf,
}
pub fn read_config(path: &Path) -> Result<Config> {
    Ok(serde_json::from_slice(&std::fs::read(path)?)?)
}
pub fn init_logs() {
    tracing_subscriber::fmt()
        .with_target(false)
        .with_env_filter("info")
        .init();
}
pub fn key_public(path: &Path) -> Result<String> {
    Ok(crypto::public(&load_key(path)?))
}
pub async fn unix_listener(path: &Path) -> Result<tokio::net::UnixListener> {
    use std::os::unix::fs::PermissionsExt;
    if path.exists() {
        ensure!(
            tokio::net::UnixStream::connect(path).await.is_err(),
            "socket already serving"
        );
        std::fs::remove_file(path)?;
    }
    let listener = tokio::net::UnixListener::bind(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o660))?;
    Ok(listener)
}
