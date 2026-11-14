use crate::crypto;
use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Peer {
    pub public_key: String,
    pub slot: u16,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PeerSet {
    pub revision: i64,
    pub peers: Vec<Peer>,
}
impl PeerSet {
    pub fn validate(&self) -> Result<()> {
        ensure!(
            self.revision >= 0 && self.peers.len() <= 250,
            "invalid peer set"
        );
        let mut keys = std::collections::HashSet::new();
        let mut slots = std::collections::HashSet::new();
        for p in &self.peers {
            crypto::wg_public_valid(&p.public_key)?;
            ensure!(
                (2..=251).contains(&p.slot) && keys.insert(&p.public_key) && slots.insert(p.slot),
                "duplicate or invalid peer"
            );
        }
        Ok(())
    }
    pub fn set_args(&self, existing: &[String]) -> Result<Vec<String>> {
        use base64::Engine;
        self.validate()?;
        ensure!(existing.len() <= 250, "too many existing peers");
        let engine = base64::engine::general_purpose::STANDARD;
        let mut args = Vec::new();
        let mut desired = std::collections::HashSet::new();
        for p in &self.peers {
            let key = engine.encode(crypto::decode(&p.public_key)?);
            desired.insert(key.clone());
            args.extend([
                "peer".to_owned(),
                key,
                "allowed-ips".to_owned(),
                format!("10.77.0.{}/32,fd77:6474:7670::{:x}/128", p.slot, p.slot),
            ]);
        }
        for key in existing {
            let decoded = engine.decode(key)?;
            ensure!(
                decoded.len() == 32 && engine.encode(&decoded) == *key,
                "invalid existing peer"
            );
            if !desired.contains(key) {
                args.extend(["peer".to_owned(), key.clone(), "remove".to_owned()]);
            }
        }
        Ok(args)
    }
}
