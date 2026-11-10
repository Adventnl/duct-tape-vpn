use serde::{Deserialize, Serialize};
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Desired {
    Off,
    On,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Tunnel {
    Down,
    Connecting,
    Up,
    Reconnecting,
    Failed,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Protection {
    None,
    Blocked,
    Enforced,
    Limited,
    Unknown,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct State {
    pub desired: Desired,
    pub tunnel: Tunnel,
    pub protection: Protection,
    pub permission: bool,
    pub verified_at: Option<i64>,
}
impl State {
    pub fn protected(&self, now: i64) -> bool {
        self.desired == Desired::On
            && self.tunnel == Tunnel::Up
            && self.protection == Protection::Enforced
            && self.permission
            && self.verified_at.is_some_and(|t| t <= now && now - t <= 30)
    }
    pub fn retry_delay(attempt: u32) -> u64 {
        1u64 << attempt.min(6)
    }
}
