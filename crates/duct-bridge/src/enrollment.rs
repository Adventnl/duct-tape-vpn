use super::*;
use reqwest::blocking::Client;
use serde::{Serialize, de::DeserializeOwned};
fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_secs() as i64
}
fn client() -> Result<Client> {
    Ok(Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .connect_timeout(std::time::Duration::from_secs(5))
        .timeout(std::time::Duration::from_secs(15))
        .build()?)
}
fn origin(s: &str) -> Result<String> {
    let u = reqwest::Url::parse(s)?;
    ensure!(
        u.scheme() == "https"
            && u.host_str().is_some()
            && u.username().is_empty()
            && u.password().is_none()
            && u.path() == "/"
            && u.query().is_none()
            && u.fragment().is_none(),
        "invalid HTTPS origin"
    );
    Ok(s.trim_end_matches('/').into())
}
fn post<T: Serialize, R: DeserializeOwned>(url: &str, v: &T) -> Result<R> {
    use std::io::Read;
    let mut r = client()?.post(url).json(v).send()?.error_for_status()?;
    let mut body = Vec::new();
    r.by_ref().take(65537).read_to_end(&mut body)?;
    ensure!(body.len() <= 65536, "response too large");
    Ok(serde_json::from_slice(&body)?)
}
fn verified(key: &str, domain: &str, r: Signed<Value>) -> Result<Value> {
    crypto::verify(key, &bytes(domain, &r.payload)?, &r.signature)?;
    Ok(r.payload)
}
pub fn begin(v: &Value) -> Result<Value> {
    let link = field(v, "invitation")?;
    ensure!(link.len() < 4096, "invitation too long");
    let i: Value = serde_json::from_slice(&crypto::decode(
        link.strip_prefix("ducttape://pair#")
            .context("invalid invitation")?,
    )?)?;
    ensure!(
        i["expires_at"].as_i64().context("expiry required")? > now(),
        "expired invitation"
    );
    let base = origin(field(&i, "origin")?)?;
    let server_key = field(&i, "server_key")?;
    let keys = &v["keys"];
    let enrollment = Enrollment {
        server_id: crypto::hash(crypto::decode(server_key)?),
        invitation: field(&i, "token")?.into(),
        name: field(v, "name")?.into(),
        platform: serde_json::from_value(v["platform"].clone())?,
        signing_key: field(keys, "signing_key")?.into(),
        wireguard_key: field(keys, "wireguard_key")?.into(),
    };
    let challenge: Signed<Challenge> = post(&format!("{base}/v1/challenge"), &enrollment)?;
    let proof = call(
        json!({"op":"answer","challenge":challenge,"enrollment":enrollment,"server_key":server_key,"wireguard_private":keys["wireguard_private"],"signing_private":keys["signing_private"],"now":now()}),
    )?;
    let claim: Claim = serde_json::from_value(proof["claim"].clone())?;
    Ok(
        json!({"session":{"origin":base,"server_key":server_key,"id":claim.id,"fingerprint":proof["fingerprint"]},"claim":claim,"fingerprint":proof["fingerprint"]}),
    )
}
pub fn finish(v: &Value) -> Result<Value> {
    let checkpoint = &v["checkpoint"];
    let session = &checkpoint["session"];
    let base = origin(field(session, "origin")?)?;
    let server_key = field(session, "server_key")?;
    let claim: Claim = serde_json::from_value(checkpoint["claim"].clone())?;
    ensure!(claim.id == field(session, "id")?, "checkpoint mismatch");
    let response: Signed<Value> = post(&format!("{base}/v1/claim"), &claim)?;
    let result = verified(server_key, "enrollment-result", response)?;
    ensure!(
        result["id"] == claim.id && result["fingerprint"] == checkpoint["fingerprint"],
        "enrollment result mismatch"
    );
    Ok(json!({"status":"pending","fingerprint":checkpoint["fingerprint"]}))
}

pub fn poll(v: &Value) -> Result<Value> {
    let s = &v["session"];
    let server_key = field(s, "server_key")?;
    let base = origin(field(s, "origin")?)?;
    let auth = PollAuth {
        server_id: crypto::hash(crypto::decode(server_key)?),
        id: field(s, "id")?.into(),
        nonce: crypto::random(),
        expires_at: now() + 30,
    };
    let key = p256::ecdsa::SigningKey::from_slice(&crypto::decode(field(
        &v["keys"],
        "signing_private",
    )?)?)?;
    let req = Poll {
        id: auth.id.clone(),
        nonce: auth.nonce.clone(),
        expires_at: auth.expires_at,
        signature: crypto::sign(&key, &bytes("poll", &auth)?),
    };
    let response = verified(
        server_key,
        "poll-result",
        post(&format!("{base}/v1/poll"), &req)?,
    )?;
    ensure!(response["nonce"] == auth.nonce, "response mismatch");
    let result = &response["result"];
    if result["status"] == "ready" {
        let c: PeerConfig = serde_json::from_value(result["config"].clone())?;
        ensure!(
            c.device_id == auth.id
                && c.server_id == auth.server_id
                && c.server_signing_key == server_key,
            "configuration binding mismatch"
        );
        endpoint_valid(&c.endpoint)?;
        crypto::wg_public_valid(&c.server_wireguard_key)?;
    }
    Ok(result.clone())
}
pub fn admin(v: &Value) -> Result<Value> {
    let s = &v["session"];
    let server_key = field(s, "server_key")?;
    let base = origin(field(v, "admin_origin")?)?;
    // Caller supplies an independently authenticated Owner signature; no client WireGuard key authorizes administration.
    let req: Signed<AdminRequest> = serde_json::from_value(v["request"].clone())?;
    ensure!(
        req.payload.server_id == crypto::hash(crypto::decode(server_key)?),
        "server mismatch"
    );
    let result = verified(
        server_key,
        "admin-result",
        post(&format!("{base}/v1/admin"), &req)?,
    )?;
    ensure!(result["nonce"] == req.payload.nonce, "response mismatch");
    Ok(result)
}
