use duct_core::{crypto, helper::*, policy::*, protocol::*, registry::Registry};
use p256::ecdsa::SigningKey;
use serde_json::Value;
const NOW: i64 = 1_800_000_000;
struct Fixture {
    db: Registry,
    owner: SigningKey,
    server: SigningKey,
    _dir: tempfile::TempDir,
}
impl Fixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let server = crypto::signing_key();
        let owner = crypto::signing_key();
        let mut db = Registry::open(dir.path().join("test.db"), server.clone()).unwrap();
        db.bootstrap(
            &crypto::public(&owner),
            &crypto::wg_keypair().1,
            &crypto::wg_keypair().1,
            "vpn.example.org:51820",
        )
        .unwrap();
        Self {
            db,
            owner,
            server,
            _dir: dir,
        }
    }
    fn request(&self, op: Operation) -> Signed<AdminRequest> {
        signed(
            "admin",
            AdminRequest {
                server_id: self.db.server_id(),
                nonce: crypto::random(),
                expires_at: NOW + 30,
                operation: op,
            },
            &self.owner,
        )
        .unwrap()
    }
    fn admin(&mut self, op: Operation) -> Value {
        let req = self.request(op);
        self.db.admin(req, NOW).unwrap().payload["result"].clone()
    }
    fn invite(&mut self) -> String {
        self.admin(Operation::Invite { ttl_seconds: 300 })["token"]
            .as_str()
            .unwrap()
            .into()
    }
    fn enrollment(&self, token: String) -> (Enrollment, SigningKey, Vec<u8>) {
        let signing = crypto::signing_key();
        let (private, public) = crypto::wg_keypair();
        (
            Enrollment {
                server_id: self.db.server_id(),
                invitation: token,
                name: "Phone".into(),
                platform: Platform::Android,
                signing_key: crypto::public(&signing),
                wireguard_key: public,
            },
            signing,
            private,
        )
    }
    fn claim(&mut self, token: String) -> (Claim, String, SigningKey) {
        let (req, key, private) = self.enrollment(token);
        let c = self.db.challenge(req, NOW).unwrap();
        crypto::verify(
            &crypto::public(&self.server),
            &bytes("challenge", &c.payload).unwrap(),
            &c.signature,
        )
        .unwrap();
        let proof = String::from_utf8(
            crypto::open(&private, &c.payload.sealed, c.payload.binding.as_bytes()).unwrap(),
        )
        .unwrap();
        let auth = Possession {
            challenge_id: c.payload.id.clone(),
            server_id: self.db.server_id(),
            binding: c.payload.binding.clone(),
            proof: proof.clone(),
        };
        (
            Claim {
                id: c.payload.id,
                proof,
                signature: crypto::sign(&key, &bytes("possession", &auth).unwrap()),
            },
            c.payload.binding,
            key,
        )
    }
    fn poll(&mut self, id: String, key: &SigningKey) -> Value {
        let auth = PollAuth {
            server_id: self.db.server_id(),
            id: id.clone(),
            nonce: crypto::random(),
            expires_at: NOW + 30,
        };
        self.db
            .poll(
                Poll {
                    id,
                    nonce: auth.nonce.clone(),
                    expires_at: auth.expires_at,
                    signature: crypto::sign(key, &bytes("poll", &auth).unwrap()),
                },
                NOW,
            )
            .unwrap()
            .payload["result"]
            .clone()
    }
}
#[test]
fn full_journey_and_persistent_revocation() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (claim, fingerprint, key) = f.claim(token);
    let id = claim.id.clone();
    f.db.claim(claim, NOW).unwrap();
    assert_eq!(f.poll(id.clone(), &key)["status"], "pending");
    assert_eq!(f.db.desired_peers().unwrap().peers.len(), 1);
    f.admin(Operation::Approve {
        id: id.clone(),
        fingerprint,
    });
    assert_eq!(f.poll(id.clone(), &key)["status"], "provisioning");
    let desired = f.db.desired_peers().unwrap();
    assert_eq!(desired.peers.len(), 2);
    f.db.mark_applied(desired.revision).unwrap();
    let config = f.poll(id.clone(), &key);
    assert_eq!(config["status"], "ready");
    assert_eq!(config["config"]["address"], "10.77.0.3/32");
    f.admin(Operation::Revoke { id: id.clone() });
    assert_eq!(f.poll(id.clone(), &key)["status"], "revoked");
    drop(f.db);
    let db = Registry::open(f._dir.path().join("test.db"), f.server).unwrap();
    assert_eq!(db.desired_peers().unwrap().peers.len(), 1);
    db.check().unwrap();
}
#[test]
fn admin_replay_and_operation_substitution() {
    let mut f = Fixture::new();
    let req = f.request(Operation::List);
    f.db.admin(req.clone(), NOW).unwrap();
    assert!(f.db.admin(req, NOW).is_err());
    let mut req = f.request(Operation::List);
    req.payload.operation = Operation::Invite { ttl_seconds: 300 };
    assert!(f.db.admin(req, NOW).is_err());
}
#[test]
fn client_cannot_admin_or_become_owner() {
    let mut f = Fixture::new();
    let mut req = f.request(Operation::List);
    req.signature = crypto::sign(
        &crypto::signing_key(),
        &bytes("admin", &req.payload).unwrap(),
    );
    assert!(f.db.admin(req, NOW).is_err());
    assert!(serde_json::from_str::<Operation>(r#"{"type":"promote","id":"x"}"#).is_err());
    assert!(serde_json::from_str::<Enrollment>(r#"{"role":"owner"}"#).is_err());
}
#[test]
fn invitation_is_single_use_and_claim_replay_fails() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (a, _, _) = f.claim(token.clone());
    let (b, _, _) = f.claim(token);
    f.db.claim(a.clone(), NOW).unwrap();
    assert!(f.db.claim(a, NOW).is_err());
    assert!(f.db.claim(b, NOW).is_err());
}
#[test]
fn concurrent_invitation_claims_are_atomic() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (a, _, _) = f.claim(token.clone());
    let (b, _, _) = f.claim(token);
    let path = f._dir.path().join("test.db");
    let mut db2 = Registry::open(path, f.server.clone()).unwrap();
    let thread = std::thread::spawn(move || db2.claim(b, NOW).is_ok());
    let first = f.db.claim(a, NOW).is_ok();
    let second = thread.join().unwrap();
    assert_ne!(first, second);
}
#[test]
fn invalid_wireguard_possession_never_claims_invitation() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (mut c, _, _) = f.claim(token.clone());
    c.proof = crypto::random();
    assert!(f.db.claim(c, NOW).is_err());
    let (c, _, _) = f.claim(token);
    f.db.claim(c, NOW).unwrap();
}
#[test]
fn key_substitution_and_aad_fail() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (e, _, _) = f.enrollment(token);
    let c = f.db.challenge(e, NOW).unwrap();
    assert!(
        crypto::open(
            &crypto::wg_keypair().0,
            &c.payload.sealed,
            c.payload.binding.as_bytes()
        )
        .is_err()
    );
    assert!(
        crypto::open(
            &crypto::wg_keypair().0,
            &c.payload.sealed,
            b"different server"
        )
        .is_err()
    );
}
#[test]
fn signature_key_substitution_fails() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (mut c, _, _) = f.claim(token);
    c.signature = crypto::sign(&crypto::signing_key(), b"wrong");
    assert!(f.db.claim(c, NOW).is_err());
}
#[test]
fn invitation_expiry_cancellation_and_challenge_expiry() {
    let mut f = Fixture::new();
    let result = f.admin(Operation::Invite { ttl_seconds: 30 });
    let token = result["token"].as_str().unwrap().to_string();
    let (e, _, _) = f.enrollment(token);
    assert!(f.db.challenge(e, NOW + 31).is_err());
    let token = f.invite();
    let (c, _, _) = f.claim(token);
    assert!(f.db.claim(c, NOW + 121).is_err());
    f.admin(Operation::CancelInvite {
        id: result["id"].as_str().unwrap().into(),
    });
}
#[test]
fn fingerprint_required_and_rejection_permanent() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (c, fp, k) = f.claim(token);
    let id = c.id.clone();
    f.db.claim(c, NOW).unwrap();
    let req = f.request(Operation::Approve {
        id: id.clone(),
        fingerprint: crypto::random(),
    });
    assert!(f.db.admin(req, NOW).is_err());
    f.admin(Operation::Reject { id: id.clone() });
    let req = f.request(Operation::Approve {
        id: id.clone(),
        fingerprint: fp,
    });
    assert!(f.db.admin(req, NOW).is_err());
    assert_eq!(f.poll(id, &k)["status"], "rejected");
}
#[test]
fn recovery_invalidates_owner_and_all_invitations() {
    let mut f = Fixture::new();
    let old = f.request(Operation::List);
    let token = f.invite();
    let (c, _, _) = f.claim(token.clone());
    f.db.recover(
        &crypto::public(&crypto::signing_key()),
        &crypto::wg_keypair().1,
    )
    .unwrap();
    assert!(f.db.admin(old, NOW).is_err());
    assert!(f.db.claim(c, NOW).is_err());
    let (e, _, _) = f.enrollment(token);
    assert!(f.db.challenge(e, NOW).is_err());
    assert_eq!(f.db.desired_peers().unwrap().peers.len(), 1);
}
#[test]
fn bounds_and_duplicate_keys() {
    let mut f = Fixture::new();
    let token = f.invite();
    let (mut e, _, _) = f.enrollment(token.clone());
    e.name = "x".repeat(81);
    assert!(f.db.challenge(e, NOW).is_err());
    let (e, _, _) = f.enrollment(token);
    for _ in 0..8 {
        f.db.challenge(e.clone(), NOW).unwrap();
    }
    assert!(f.db.challenge(e, NOW).is_err());
    for endpoint in [
        "x:5/command",
        "user@host:1",
        "host:0\n",
        "host",
        "host:10?x=1",
        "host:0",
    ] {
        assert!(endpoint_valid(endpoint).is_err(), "{endpoint}");
    }
}
#[test]
fn identity_and_auth_expiration_fail_closed() {
    let mut f = Fixture::new();
    let mut req = f.request(Operation::List);
    req.payload.server_id = crypto::random();
    assert!(f.db.admin(req, NOW).is_err());
    let req = f.request(Operation::List);
    assert!(f.db.admin(req, NOW + 31).is_err());
    assert!(
        f.db.bootstrap(
            &crypto::public(&f.owner),
            &crypto::wg_keypair().1,
            &crypto::wg_keypair().1,
            "x:5"
        )
        .is_err()
    );
}
#[test]
fn helper_restricts_addresses_and_commands() {
    let key = crypto::wg_keypair().1;
    let good = PeerSet {
        revision: 1,
        peers: vec![Peer {
            public_key: key.clone(),
            slot: 3,
        }],
    };
    let conf = good.syncconf().unwrap();
    assert!(conf.contains("10.77.0.3/32, fd77:6474:7670::3/128"));
    assert!(
        PeerSet {
            revision: 1,
            peers: vec![Peer {
                public_key: key.clone(),
                slot: 1
            }]
        }
        .validate()
        .is_err()
    );
    assert!(
        PeerSet {
            revision: 1,
            peers: vec![
                Peer {
                    public_key: key,
                    slot: 3
                };
                2
            ]
        }
        .validate()
        .is_err()
    );
    assert!(
        serde_json::from_str::<PeerSet>(r#"{"revision":1,"peers":[],"command":"sh"}"#).is_err()
    );
}
#[test]
fn no_protection_claim_without_fresh_verification() {
    let mut s = State {
        desired: Desired::On,
        tunnel: Tunnel::Up,
        protection: Protection::Enforced,
        permission: true,
        verified_at: Some(NOW),
    };
    assert!(s.protected(NOW + 29));
    assert!(!s.protected(NOW + 31));
    s.protection = Protection::Limited;
    assert!(!s.protected(NOW));
    s.protection = Protection::Enforced;
    s.tunnel = Tunnel::Failed;
    assert!(!s.protected(NOW));
    assert_eq!(State::retry_delay(1000), 64);
}
#[test]
fn migration_backup_and_future_schema() {
    let mut f = Fixture::new();
    let token = f.invite();
    let backup = f._dir.path().join("snapshot.db");
    f.db.backup(&backup).unwrap();
    let mut restored = Registry::open(&backup, f.server.clone()).unwrap();
    restored.check().unwrap();
    let (e, _, _) = f.enrollment(token);
    restored.challenge(e, NOW).unwrap();
    drop(restored);
    let conn = rusqlite::Connection::open(&backup).unwrap();
    conn.pragma_update(None, "user_version", 999).unwrap();
    drop(conn);
    assert!(Registry::open(&backup, f.server).is_err());
}
#[test]
fn signed_configuration_endpoint_rotation_retains_identity() {
    let mut f = Fixture::new();
    let id = f.db.server_id();
    f.admin(Operation::Endpoint {
        endpoint: "new.example.org:51821".into(),
    });
    assert_eq!(id, f.db.server_id());
    let req = f.request(Operation::Revoke { id: "owner".into() });
    assert!(f.db.admin(req, NOW).is_err());
}

#[test]
fn release_version_cannot_be_rebound_and_owner_bundle_is_bound() {
    let mut f = Fixture::new();
    f.admin(Operation::ApproveRelease {
        sha256: "ab".repeat(32),
        version: 1,
    });
    let req = f.request(Operation::ApproveRelease {
        sha256: "cd".repeat(32),
        version: 1,
    });
    assert!(f.db.admin(req, NOW).is_err());
    let bundle =
        f.db.owner_bundle("https://vpn.example.org", "https://admin.example.org:9443")
            .unwrap();
    crypto::verify(
        &crypto::public(&f.server),
        &bytes("owner-bootstrap", &bundle.payload).unwrap(),
        &bundle.signature,
    )
    .unwrap();
    assert_eq!(
        bundle.payload["owner_signing_key"],
        crypto::public(&f.owner)
    );
    assert_eq!(bundle.payload["config"]["device_id"], "owner");
    assert!(
        f.db.owner_bundle("http://vpn.example.org", "https://admin.example.org")
            .is_err()
    );
}

#[test]
fn standard_tls_port_is_valid_for_udp_transport() {
    assert!(endpoint_valid("vpn.example.org:443").is_ok());
    assert!(endpoint_valid("[2001:db8::1]:443").is_ok());
    assert!(endpoint_valid("vpn.example.org:0").is_err());
}
