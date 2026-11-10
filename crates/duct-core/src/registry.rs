use crate::{
    crypto,
    helper::{Peer, PeerSet},
    protocol::*,
};
use anyhow::{Context, Result, ensure};
use p256::ecdsa::SigningKey;
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde_json::{Value, json};

pub struct Registry {
    conn: Connection,
    identity: SigningKey,
}
impl Registry {
    pub fn open(path: impl AsRef<std::path::Path>, identity: SigningKey) -> Result<Self> {
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create(true).truncate(false);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        options.open(path.as_ref())?;
        let conn = Connection::open(path)?;
        conn.busy_timeout(std::time::Duration::from_secs(3))?;
        conn.execute_batch(
            "PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;",
        )?;
        let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
        ensure!(version <= 1, "database is from a newer server");
        if version == 0 {
            conn.execute_batch(include_str!("schema.sql"))?;
        }
        Ok(Self { conn, identity })
    }
    pub fn server_id(&self) -> String {
        crypto::hash(crypto::decode(&crypto::public(&self.identity)).expect("own public key"))
    }
    pub fn bootstrap(
        &mut self,
        owner_signing: &str,
        owner_wg: &str,
        server_wg: &str,
        endpoint: &str,
    ) -> Result<()> {
        crypto::signing_public_valid(owner_signing)?;
        crypto::wg_public_valid(owner_wg)?;
        crypto::wg_public_valid(server_wg)?;
        endpoint_valid(endpoint)?;
        ensure!(owner_wg != server_wg, "server and owner keys must differ");
        let server_id = self.server_id();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let count: i64 = tx.query_row("SELECT count(*) FROM settings", [], |r| r.get(0))?;
        ensure!(count == 0, "already bootstrapped; use recovery");
        for (k, v) in [
            ("server_id", server_id),
            ("server_wg", server_wg.into()),
            ("endpoint", endpoint.into()),
            ("revision", "1".into()),
            ("applied", "0".into()),
        ] {
            tx.execute("INSERT INTO settings VALUES (?1,?2)", params![k, v])?;
        }
        tx.execute("INSERT INTO devices(id,name,platform,signing_key,wg_key,status,slot,revision,fingerprint,role) VALUES ('owner','Owner MacBook','macos',?1,?2,'active',2,1,'bootstrap','owner')",params![owner_signing,owner_wg])?;
        tx.commit()?;
        Ok(())
    }
    fn get(&self, key: &str) -> Result<String> {
        Ok(self
            .conn
            .query_row("SELECT value FROM settings WHERE key=?1", [key], |r| {
                r.get(0)
            })?)
    }
    pub fn challenge(&mut self, mut req: Enrollment, now: i64) -> Result<Signed<Challenge>> {
        ensure!(
            req.server_id == self.server_id() && self.get("server_id")? == req.server_id,
            "wrong server identity"
        );
        crypto::validate_name(&req.name)?;
        crypto::signing_public_valid(&req.signing_key)?;
        crypto::wg_public_valid(&req.wireguard_key)?;
        ensure!(req.wireguard_key != self.get("server_wg")?, "reserved key");
        ensure!(
            crypto::decode(&req.invitation)?.len() == 32,
            "invalid invitation"
        );
        req.invitation = crypto::hash(&req.invitation);
        let id = crypto::random();
        let secret = crypto::random();
        let binding = crypto::hash(bytes("enrollment", &req)?);
        let sealed = crypto::seal(&req.wireguard_key, secret.as_bytes(), binding.as_bytes())?;
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute("DELETE FROM challenges WHERE expires_at < ?1", [now])?;
        let valid:bool=tx.query_row("SELECT EXISTS(SELECT 1 FROM invitations WHERE token_hash=?1 AND expires_at>?2 AND state='open')",params![req.invitation,now],|r|r.get(0))?;
        ensure!(valid, "invitation unavailable");
        let count: i64 = tx.query_row("SELECT count(*) FROM challenges", [], |r| r.get(0))?;
        ensure!(count < 256, "challenge capacity reached");
        let count: i64 = tx.query_row(
            "SELECT count(*) FROM challenges WHERE invitation_hash=?1",
            [&req.invitation],
            |r| r.get(0),
        )?;
        ensure!(count < 8, "invitation challenge limit");
        tx.execute(
            "INSERT INTO challenges VALUES (?1,?2,?3,?4,?5,?6)",
            params![
                id,
                serde_json::to_string(&req)?,
                crypto::hash(&secret),
                binding,
                now + 120,
                req.invitation
            ],
        )?;
        tx.commit()?;
        signed(
            "challenge",
            Challenge {
                id,
                server_id: self.server_id(),
                binding,
                expires_at: now + 120,
                sealed,
            },
            &self.identity,
        )
    }
    pub fn claim(&mut self, req: Claim, now: i64) -> Result<Signed<Value>> {
        ensure!(req.id.len() <= 64 && req.proof.len() <= 64, "invalid claim");
        let server_id = self.server_id();
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let row = tx
            .query_row(
                "SELECT enrollment,proof_hash,binding,expires_at FROM challenges WHERE id=?1",
                [&req.id],
                |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                        r.get::<_, i64>(3)?,
                    ))
                },
            )
            .optional()?
            .context("challenge unavailable")?;
        ensure!(
            row.3 > now && crypto::constant_eq(&crypto::hash(&req.proof), &row.1),
            "invalid proof"
        );
        let enrollment: Enrollment = serde_json::from_str(&row.0)?;
        let possession = Possession {
            challenge_id: req.id.clone(),
            server_id,
            binding: row.2.clone(),
            proof: req.proof,
        };
        crypto::verify(
            &enrollment.signing_key,
            &bytes("possession", &possession)?,
            &req.signature,
        )?;
        let n=tx.execute("UPDATE invitations SET state='claimed' WHERE token_hash=?1 AND state='open' AND expires_at>?2",params![enrollment.invitation,now])?;
        ensure!(n == 1, "invitation already claimed");
        tx.execute("INSERT INTO devices(id,name,platform,signing_key,wg_key,status,fingerprint,role) VALUES (?1,?2,?3,?4,?5,'pending',?6,'client')",params![req.id,enrollment.name,serde_json::to_value(enrollment.platform)?.as_str(),enrollment.signing_key,enrollment.wireguard_key,row.2])?;
        tx.execute(
            "DELETE FROM challenges WHERE invitation_hash=?1",
            [enrollment.invitation],
        )?;
        tx.commit()?;
        signed(
            "enrollment-result",
            json!({"id":req.id,"status":"pending","fingerprint":row.2}),
            &self.identity,
        )
    }
    pub fn admin(&mut self, request: Signed<AdminRequest>, now: i64) -> Result<Signed<Value>> {
        let req = &request.payload;
        ensure!(
            req.server_id == self.server_id()
                && req.expires_at >= now
                && req.expires_at <= now + 60
                && crypto::decode(&req.nonce)?.len() == 32,
            "expired or invalid authorization"
        );
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let owner: String = tx.query_row(
            "SELECT signing_key FROM devices WHERE role='owner' AND status='active'",
            [],
            |r| r.get(0),
        )?;
        crypto::verify(&owner, &bytes("admin", req)?, &request.signature)?;
        tx.execute("DELETE FROM nonces WHERE expires_at<?1", [now])?;
        tx.execute(
            "INSERT INTO nonces VALUES (?1,?2)",
            params![req.nonce, req.expires_at],
        )?;
        let mut changed = false;
        let result = match &req.operation {
            Operation::Invite { ttl_seconds } => {
                ensure!(
                    (30..=900).contains(ttl_seconds),
                    "invitation TTL must be 30..900 seconds"
                );
                tx.execute(
                    "UPDATE invitations SET state='expired' WHERE expires_at<=?1 AND state='open'",
                    [now],
                )?;
                let count: i64 = tx.query_row(
                    "SELECT count(*) FROM invitations WHERE state='open'",
                    [],
                    |r| r.get(0),
                )?;
                ensure!(count < 128, "invitation limit");
                let token = crypto::random();
                let id = crypto::random();
                tx.execute(
                    "INSERT INTO invitations VALUES (?1,?2,?3,'open')",
                    params![id, crypto::hash(&token), now + ttl_seconds],
                )?;
                json!({"id":id,"token":token,"expires_at":now+ttl_seconds})
            }
            Operation::CancelInvite { id } => {
                tx.execute(
                    "UPDATE invitations SET state='cancelled' WHERE id=?1 AND state='open'",
                    [id],
                )?;
                json!({"cancelled":id})
            }
            Operation::List => {
                let mut stmt=tx.prepare("SELECT id,name,platform,status,fingerprint,role,slot,revision FROM devices ORDER BY role DESC,id")?;
                let rows=stmt.query_map([],|r|Ok(json!({"id":r.get::<_,String>(0)?,"name":r.get::<_,String>(1)?,"platform":r.get::<_,String>(2)?,"status":r.get::<_,String>(3)?,"fingerprint":r.get::<_,String>(4)?,"role":r.get::<_,String>(5)?,"slot":r.get::<_,Option<u16>>(6)?,"revision":r.get::<_,i64>(7)?})))?.collect::<rusqlite::Result<Vec<_>>>()?;
                json!({"devices":rows})
            }
            Operation::Approve { id, fingerprint } => {
                let f:String=tx.query_row("SELECT fingerprint FROM devices WHERE id=?1 AND status='pending' AND role='client'",[id],|r|r.get(0))?;
                ensure!(crypto::constant_eq(&f, fingerprint), "fingerprint mismatch");
                let slot: i64 =
                    tx.query_row("SELECT coalesce(max(slot),2)+1 FROM devices", [], |r| {
                        r.get(0)
                    })?;
                ensure!(slot <= 251, "address pool full");
                tx.execute(
                    "UPDATE devices SET status='active',slot=?2 WHERE id=?1",
                    params![id, slot],
                )?;
                changed = true;
                json!({"approved":id})
            }
            Operation::Reject { id } => {
                tx.execute("UPDATE devices SET status='rejected' WHERE id=?1 AND status='pending' AND role='client'",[id])?;
                json!({"rejected":id})
            }
            Operation::Revoke { id } => {
                ensure!(
                    id != "owner",
                    "Owner revocation requires trusted local recovery"
                );
                tx.execute(
                    "UPDATE devices SET status='revoked' WHERE id=?1 AND role='client'",
                    [id],
                )?;
                changed = true;
                json!({"revoked":id})
            }
            Operation::Rename { id, name } => {
                crypto::validate_name(name)?;
                tx.execute("UPDATE devices SET name=?2 WHERE id=?1", params![id, name])?;
                json!({"renamed":id})
            }
            Operation::Endpoint { endpoint } => {
                endpoint_valid(endpoint)?;
                tx.execute(
                    "UPDATE settings SET value=?1 WHERE key='endpoint'",
                    [endpoint],
                )?;
                changed = true;
                json!({"endpoint":endpoint})
            }
            Operation::ApproveRelease { sha256, version } => {
                ensure!(
                    sha256.len() == 64 && sha256.bytes().all(|b| b.is_ascii_hexdigit()),
                    "invalid release hash"
                );
                tx.execute(
                    "INSERT INTO approved_releases VALUES (?1,?2) ON CONFLICT(version) DO NOTHING",
                    params![version, sha256],
                )?;
                let stored: String = tx.query_row(
                    "SELECT sha256 FROM approved_releases WHERE version=?1",
                    [version],
                    |r| r.get(0),
                )?;
                ensure!(
                    &stored == sha256,
                    "release version already bound to a different artifact"
                );
                json!({"approved_release":version,"sha256":sha256})
            }
        };
        if changed {
            tx.execute(
                "UPDATE settings SET value=CAST(value AS INTEGER)+1 WHERE key='revision'",
                [],
            )?;
            tx.execute("UPDATE devices SET revision=(SELECT CAST(value AS INTEGER) FROM settings WHERE key='revision') WHERE status='active'",[])?;
        }
        tx.commit()?;
        signed(
            "admin-result",
            json!({"nonce":req.nonce,"result":result,"reconciliation":{"desired_revision":self.get("revision")?,"applied_revision":self.get("applied")?}}),
            &self.identity,
        )
    }
    pub fn poll(&mut self, p: Poll, now: i64) -> Result<Signed<Value>> {
        ensure!(
            p.expires_at >= now
                && p.expires_at <= now + 60
                && crypto::decode(&p.nonce)?.len() == 32,
            "invalid poll"
        );
        let key: String = self.conn.query_row(
            "SELECT signing_key FROM devices WHERE id=?1",
            [&p.id],
            |r| r.get(0),
        )?;
        crypto::verify(
            &key,
            &bytes(
                "poll",
                &PollAuth {
                    server_id: self.server_id(),
                    id: p.id.clone(),
                    nonce: p.nonce.clone(),
                    expires_at: p.expires_at,
                },
            )?,
            &p.signature,
        )?;
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute("DELETE FROM nonces WHERE expires_at<?1", [now])?;
        tx.execute(
            "INSERT INTO nonces VALUES (?1,?2)",
            params![p.nonce, p.expires_at],
        )?;
        let (status, slot, revision) = tx.query_row(
            "SELECT status,slot,revision FROM devices WHERE id=?1",
            [&p.id],
            |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, Option<u16>>(1)?,
                    r.get::<_, i64>(2)?,
                ))
            },
        )?;
        tx.commit()?;
        let applied: i64 = self.get("applied")?.parse()?;
        let result = if status == "active" && applied >= revision {
            let slot = slot.context("missing slot")?;
            json!({"status":"ready","config":PeerConfig{device_id:p.id,server_id:self.server_id(),server_signing_key:crypto::public(&self.identity),server_wireguard_key:self.get("server_wg")?,address:format!("10.77.0.{slot}/32"),address_v6:format!("fd77:6474:7670::{slot:x}/128"),dns:"10.77.0.1".into(),endpoint:self.get("endpoint")?,mtu:1280,revision}})
        } else {
            json!({"status":if status=="active" {"provisioning"} else {&status}})
        };
        signed(
            "poll-result",
            json!({"nonce":p.nonce,"result":result}),
            &self.identity,
        )
    }
    pub fn owner_bundle(&self, origin: &str, admin_origin: &str) -> Result<Signed<Value>> {
        for s in [origin, admin_origin] {
            let u = url::Url::parse(s)?;
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
        }
        let (wg, owner): (String, String) = self.conn.query_row(
            "SELECT wg_key,signing_key FROM devices WHERE role='owner' AND status='active'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        signed(
            "owner-bootstrap",
            json!({"session":{"origin":origin,"admin_origin":admin_origin,"server_key":crypto::public(&self.identity),"id":"owner"},"owner_signing_key":owner,"device_wireguard_key":wg,"config":PeerConfig{device_id:"owner".into(),server_id:self.server_id(),server_signing_key:crypto::public(&self.identity),server_wireguard_key:self.get("server_wg")?,address:"10.77.0.2/32".into(),address_v6:"fd77:6474:7670::2/128".into(),dns:"10.77.0.1".into(),endpoint:self.get("endpoint")?,mtu:1280,revision:self.get("revision")?.parse()?}}),
            &self.identity,
        )
    }
    pub fn desired_peers(&self) -> Result<PeerSet> {
        let mut stmt = self
            .conn
            .prepare("SELECT wg_key,slot FROM devices WHERE status='active'")?;
        let peers = stmt
            .query_map([], |r| {
                Ok(Peer {
                    public_key: r.get(0)?,
                    slot: r.get(1)?,
                })
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(PeerSet {
            revision: self.get("revision")?.parse()?,
            peers,
        })
    }
    pub fn mark_applied(&mut self, revision: i64) -> Result<()> {
        ensure!(
            self.get("revision")?.parse::<i64>()? == revision,
            "stale reconciliation"
        );
        self.conn.execute(
            "UPDATE settings SET value=?1 WHERE key='applied'",
            [revision.to_string()],
        )?;
        Ok(())
    }
    pub fn recover(&mut self, new_signing: &str, new_wg: &str) -> Result<()> {
        crypto::signing_public_valid(new_signing)?;
        crypto::wg_public_valid(new_wg)?;
        ensure!(new_wg != self.get("server_wg")?, "reserved key");
        let tx = self
            .conn
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        tx.execute("UPDATE invitations SET state='cancelled'", [])?;
        tx.execute("DELETE FROM challenges", [])?;
        tx.execute(
            "UPDATE devices SET signing_key=?1,wg_key=?2 WHERE role='owner'",
            params![new_signing, new_wg],
        )?;
        tx.execute(
            "UPDATE settings SET value=CAST(value AS INTEGER)+1 WHERE key='revision'",
            [],
        )?;
        tx.execute("UPDATE devices SET revision=(SELECT CAST(value AS INTEGER) FROM settings WHERE key='revision') WHERE status='active'",[])?;
        tx.commit()?;
        Ok(())
    }
    pub fn backup(&self, path: &std::path::Path) -> Result<()> {
        ensure!(!path.exists(), "backup destination exists");
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        options.open(path)?;
        self.conn.backup("main", path, None)?;
        Ok(())
    }
    pub fn check(&self) -> Result<()> {
        let check: String = self
            .conn
            .query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
        ensure!(check == "ok", "database integrity failure");
        ensure!(
            self.get("server_id")? == self.server_id(),
            "identity mismatch"
        );
        self.desired_peers()?.validate()?;
        Ok(())
    }
}
