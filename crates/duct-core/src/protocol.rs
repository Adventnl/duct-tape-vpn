use crate::crypto;
use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Enrollment {
    pub server_id: String,
    pub invitation: String,
    pub name: String,
    pub platform: Platform,
    pub signing_key: String,
    pub wireguard_key: String,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    Macos,
    Windows,
    Ios,
    Android,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Challenge {
    pub id: String,
    pub server_id: String,
    pub binding: String,
    pub expires_at: i64,
    pub sealed: crypto::Sealed,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Signed<T> {
    pub payload: T,
    pub signature: String,
}
pub fn bytes<T: Serialize>(domain: &str, value: &T) -> Result<Vec<u8>> {
    let mut out = format!("duct-tape/{domain}/v1\n").into_bytes();
    out.extend(serde_json::to_vec(&serde_json::to_value(value)?)?);
    Ok(out)
}
pub fn signed<T: Serialize>(
    domain: &str,
    payload: T,
    key: &p256::ecdsa::SigningKey,
) -> Result<Signed<T>> {
    let signature = crypto::sign(key, &bytes(domain, &payload)?);
    Ok(Signed { payload, signature })
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Claim {
    pub id: String,
    pub proof: String,
    pub signature: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Possession {
    pub challenge_id: String,
    pub server_id: String,
    pub binding: String,
    pub proof: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AdminRequest {
    pub server_id: String,
    pub nonce: String,
    pub expires_at: i64,
    pub operation: Operation,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Operation {
    Invite { ttl_seconds: i64 },
    CancelInvite { id: String },
    List,
    Approve { id: String, fingerprint: String },
    Reject { id: String },
    Revoke { id: String },
    Rename { id: String, name: String },
    Endpoint { endpoint: String },
    ApproveRelease { sha256: String, version: u64 },
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Poll {
    pub id: String,
    pub nonce: String,
    pub expires_at: i64,
    pub signature: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PollAuth {
    pub server_id: String,
    pub id: String,
    pub nonce: String,
    pub expires_at: i64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerConfig {
    pub device_id: String,
    pub server_id: String,
    pub server_signing_key: String,
    pub server_wireguard_key: String,
    pub address: String,
    pub address_v6: String,
    pub dns: String,
    pub endpoint: String,
    pub mtu: u16,
    pub revision: i64,
}
pub fn endpoint_valid(s: &str) -> Result<()> {
    ensure!(
        s.len() <= 253 && !s.chars().any(|c| c.is_whitespace() || c.is_control()),
        "invalid endpoint"
    );
    let url = url::Url::parse(&format!("https://{s}"))?;
    ensure!(
        url.host_str().is_some()
            && s.rsplit_once(':')
                .and_then(|(_, port)| port.parse::<u16>().ok())
                .is_some_and(|port| port > 0 && url.port_or_known_default() == Some(port))
            && url.username().is_empty()
            && url.password().is_none()
            && url.path() == "/"
            && url.query().is_none()
            && url.fragment().is_none(),
        "endpoint must be host:port"
    );
    Ok(())
}
