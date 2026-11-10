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
    pub fn syncconf(&self) -> Result<String> {
        use base64::Engine;
        self.validate()?;
        let mut text = String::new();
        for p in &self.peers {
            text.push_str(&format!(
                "[Peer]\nPublicKey = {}\nAllowedIPs = 10.77.0.{}/32, fd77:6474:7670::{:x}/128\n\n",
                base64::engine::general_purpose::STANDARD.encode(crypto::decode(&p.public_key)?),
                p.slot,
                p.slot
            ));
        }
        Ok(text)
    }
}
