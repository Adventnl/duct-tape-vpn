use anyhow::{Context, Result, ensure};
use base64::Engine;
use clap::{Parser, Subcommand, ValueEnum};
use duct_core::{crypto, protocol::*, registry::Registry};
use duct_server::{create_private, load_key, now};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    io::{Read, Write},
    path::{Path, PathBuf},
};
#[derive(Parser)]
#[command(about = "Duct-Tape VPN trusted-local and authenticated client tooling")]
struct Args {
    #[command(subcommand)]
    command: Commands,
}
#[derive(Subcommand)]
enum Commands {
    Keys {
        #[arg(long)]
        directory: PathBuf,
    },
    Bootstrap {
        #[arg(long)]
        database: PathBuf,
        #[arg(long)]
        identity: PathBuf,
        #[arg(long)]
        owner_public: PathBuf,
        #[arg(long)]
        server_wireguard: String,
        #[arg(long)]
        endpoint: String,
    },
    OwnerBundle {
        #[arg(long)]
        database: PathBuf,
        #[arg(long)]
        identity: PathBuf,
        #[arg(long)]
        origin: String,
        #[arg(long)]
        admin_origin: String,
    },
    Check {
        #[arg(long)]
        database: PathBuf,
        #[arg(long)]
        identity: PathBuf,
    },
    Recover {
        #[arg(long)]
        database: PathBuf,
        #[arg(long)]
        identity: PathBuf,
        #[arg(long)]
        owner_public: PathBuf,
    },
    Admin {
        #[arg(long)]
        socket: Option<PathBuf>,
        #[arg(long)]
        url: Option<String>,
        #[arg(long)]
        identity: PathBuf,
        #[arg(long)]
        server_key: String,
        #[arg(long)]
        operation: PathBuf,
    },
    InviteLink {
        #[arg(long)]
        result: PathBuf,
        #[arg(long)]
        server_key: String,
        #[arg(long)]
        origin: String,
    },
    Enroll {
        #[arg(long)]
        invitation: String,
        #[arg(long)]
        directory: PathBuf,
        #[arg(long)]
        name: String,
        #[arg(long, value_enum)]
        platform: Os,
    },
    Poll {
        #[arg(long)]
        directory: PathBuf,
    },
    Backup {
        #[arg(long)]
        database: PathBuf,
        #[arg(long)]
        identity: PathBuf,
        #[arg(long)]
        passphrase_file: PathBuf,
        #[arg(long)]
        output: PathBuf,
    },
    Restore {
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        passphrase_file: PathBuf,
        #[arg(long)]
        directory: PathBuf,
    },
}
#[derive(Clone, ValueEnum)]
enum Os {
    Macos,
    Windows,
    Ios,
    Android,
}
impl From<Os> for Platform {
    fn from(v: Os) -> Self {
        match v {
            Os::Macos => Self::Macos,
            Os::Windows => Self::Windows,
            Os::Ios => Self::Ios,
            Os::Android => Self::Android,
        }
    }
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PublicKeys {
    signing_key: String,
    wireguard_key: String,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Invitation {
    origin: String,
    server_key: String,
    token: String,
    expires_at: i64,
}
#[derive(Serialize, Deserialize)]
struct Session {
    origin: String,
    server_key: String,
    id: String,
}
fn private_dir(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::create_dir(path)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    Ok(())
}
fn new_keys(dir: &Path) -> Result<PublicKeys> {
    let signing = crypto::signing_key();
    let (secret, public) = crypto::wg_keypair();
    create_private(&dir.join("signing.key"), signing.to_bytes().as_slice())?;
    create_private(&dir.join("wireguard.key"), &secret)?;
    let keys = PublicKeys {
        signing_key: crypto::public(&signing),
        wireguard_key: public,
    };
    create_private(&dir.join("public.json"), &serde_json::to_vec_pretty(&keys)?)?;
    Ok(keys)
}
fn client() -> Result<reqwest::Client> {
    Ok(reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .timeout(std::time::Duration::from_secs(10))
        .build()?)
}
fn origin_valid(s: &str) -> Result<()> {
    let u = reqwest::Url::parse(s)?;
    ensure!(
        u.scheme() == "https"
            && u.host_str().is_some()
            && u.username().is_empty()
            && u.password().is_none()
            && u.path() == "/"
            && u.query().is_none()
            && u.fragment().is_none(),
        "HTTPS origin required"
    );
    Ok(())
}
async fn post<T: Serialize, R: serde::de::DeserializeOwned>(
    client: &reqwest::Client,
    url: String,
    body: &T,
) -> Result<R> {
    let r = client
        .post(url)
        .json(body)
        .send()
        .await?
        .error_for_status()?;
    ensure!(
        r.content_length().unwrap_or(0) <= 65536,
        "oversized response"
    );
    let b = r.bytes().await?;
    ensure!(b.len() <= 65536, "oversized response");
    Ok(serde_json::from_slice(&b)?)
}
fn verify<T: Serialize>(key: &str, domain: &str, response: &Signed<T>) -> Result<()> {
    crypto::verify(key, &bytes(domain, &response.payload)?, &response.signature)
}
fn passphrase(file: &Path) -> Result<age::secrecy::SecretString> {
    let s = zeroize::Zeroizing::new(std::fs::read_to_string(file)?);
    ensure!(
        s.trim_end().len() >= 20,
        "use a strong passphrase of at least 20 characters"
    );
    Ok(s.trim_end().to_owned().into())
}
#[tokio::main]
async fn main() -> Result<()> {
    match Args::parse().command {
        Commands::Keys { directory } => {
            private_dir(&directory)?;
            let public = new_keys(&directory)?;
            println!("{}", serde_json::to_string_pretty(&public)?);
        }
        Commands::Bootstrap {
            database,
            identity,
            owner_public,
            server_wireguard,
            endpoint,
        } => {
            let key = crypto::signing_key();
            create_private(&identity, key.to_bytes().as_slice())?;
            let owner: PublicKeys = serde_json::from_slice(&std::fs::read(owner_public)?)?;
            let mut r = Registry::open(database, key)?;
            r.bootstrap(
                &owner.signing_key,
                &owner.wireguard_key,
                &server_wireguard,
                &endpoint,
            )?;
            println!(
                "server_id={} server_key={}",
                r.server_id(),
                duct_server::key_public(&identity)?
            );
        }
        Commands::OwnerBundle {
            database,
            identity,
            origin,
            admin_origin,
        } => {
            let r = Registry::open(database, load_key(&identity)?)?;
            println!(
                "{}",
                serde_json::to_string_pretty(&r.owner_bundle(&origin, &admin_origin)?)?
            );
        }
        Commands::Check { database, identity } => {
            Registry::open(database, load_key(&identity)?)?.check()?;
            println!("registry integrity and identity verified");
        }
        Commands::Recover {
            database,
            identity,
            owner_public,
        } => {
            let p: PublicKeys = serde_json::from_slice(&std::fs::read(owner_public)?)?;
            Registry::open(database, load_key(&identity)?)?
                .recover(&p.signing_key, &p.wireguard_key)?;
            println!(
                "Owner replaced; invitations invalidated; peer removal queued. Reconcile before restoring external access."
            );
        }
        Commands::Admin {
            socket,
            url,
            identity,
            server_key,
            operation,
        } => {
            let req = AdminRequest {
                server_id: crypto::hash(crypto::decode(&server_key)?),
                nonce: crypto::random(),
                expires_at: now() + 30,
                operation: serde_json::from_slice(&std::fs::read(operation)?)?,
            };
            let signed = signed("admin", req.clone(), &load_key(&identity)?)?;
            let (client, url) = if let Some(socket) = socket {
                ensure!(url.is_none(), "choose socket or HTTPS");
                (
                    reqwest::Client::builder()
                        .unix_socket(socket)
                        .timeout(std::time::Duration::from_secs(10))
                        .build()?,
                    "http://localhost/v1/admin".into(),
                )
            } else {
                let url = url.context("private HTTPS URL required")?;
                origin_valid(&url)?;
                (client()?, format!("{}/v1/admin", url.trim_end_matches('/')))
            };
            let r: Signed<Value> = post(&client, url, &signed).await?;
            verify(&server_key, "admin-result", &r)?;
            ensure!(r.payload["nonce"] == req.nonce, "response nonce mismatch");
            println!("{}", serde_json::to_string_pretty(&r)?);
        }
        Commands::InviteLink {
            result,
            server_key,
            origin,
        } => {
            origin_valid(&origin)?;
            let r: Signed<Value> = serde_json::from_slice(&std::fs::read(result)?)?;
            verify(&server_key, "admin-result", &r)?;
            let i = Invitation {
                origin,
                server_key,
                token: r.payload["result"]["token"]
                    .as_str()
                    .context("invitation token missing")?
                    .into(),
                expires_at: r.payload["result"]["expires_at"]
                    .as_i64()
                    .context("expiry missing")?,
            };
            ensure!(i.expires_at > now(), "expired invitation");
            // Fragment keeps invitation credentials out of HTTP request paths and access logs.
            println!(
                "ducttape://pair#{}",
                crypto::encode(serde_json::to_vec(&i)?)
            );
        }
        Commands::Enroll {
            invitation,
            directory,
            name,
            platform,
        } => {
            let encoded = invitation
                .strip_prefix("ducttape://pair#")
                .context("invalid invitation link")?;
            let i: Invitation = serde_json::from_slice(&crypto::decode(encoded)?)?;
            origin_valid(&i.origin)?;
            ensure!(i.expires_at > now(), "expired invitation");
            crypto::signing_public_valid(&i.server_key)?;
            private_dir(&directory)?;
            let keys = new_keys(&directory)?;
            let key = load_key(&directory.join("signing.key"))?;
            let enrollment = Enrollment {
                server_id: crypto::hash(crypto::decode(&i.server_key)?),
                invitation: i.token.clone(),
                name,
                platform: platform.into(),
                signing_key: keys.signing_key,
                wireguard_key: keys.wireguard_key,
            };
            let origin = i.origin.trim_end_matches('/');
            let client = client()?;
            let challenge: Signed<Challenge> =
                post(&client, format!("{origin}/v1/challenge"), &enrollment).await?;
            verify(&i.server_key, "challenge", &challenge)?;
            let mut binding = enrollment.clone();
            binding.invitation = crypto::hash(&binding.invitation);
            ensure!(
                challenge.payload.server_id == enrollment.server_id
                    && challenge.payload.binding == crypto::hash(bytes("enrollment", &binding)?)
                    && challenge.payload.expires_at > now(),
                "challenge substitution"
            );
            let private = zeroize::Zeroizing::new(std::fs::read(directory.join("wireguard.key"))?);
            let proof = String::from_utf8(crypto::open(
                &private,
                &challenge.payload.sealed,
                challenge.payload.binding.as_bytes(),
            )?)?;
            let possession = Possession {
                challenge_id: challenge.payload.id.clone(),
                server_id: enrollment.server_id,
                binding: challenge.payload.binding.clone(),
                proof: proof.clone(),
            };
            let claim = Claim {
                id: challenge.payload.id,
                proof,
                signature: crypto::sign(&key, &bytes("possession", &possession)?),
            };
            let result: Signed<Value> = post(&client, format!("{origin}/v1/claim"), &claim).await?;
            verify(&i.server_key, "enrollment-result", &result)?;
            ensure!(
                result.payload["id"] == claim.id
                    && result.payload["fingerprint"] == challenge.payload.binding,
                "result substitution"
            );
            create_private(
                &directory.join("session.json"),
                &serde_json::to_vec(&Session {
                    origin: i.origin,
                    server_key: i.server_key,
                    id: claim.id,
                })?,
            )?;
            println!(
                "Pending Owner approval. Compare fingerprint: {}",
                challenge.payload.binding
            );
        }
        Commands::Poll { directory } => {
            let s: Session =
                serde_json::from_slice(&std::fs::read(directory.join("session.json"))?)?;
            origin_valid(&s.origin)?;
            let auth = PollAuth {
                server_id: crypto::hash(crypto::decode(&s.server_key)?),
                id: s.id,
                nonce: crypto::random(),
                expires_at: now() + 30,
            };
            let p = Poll {
                id: auth.id.clone(),
                nonce: auth.nonce.clone(),
                expires_at: auth.expires_at,
                signature: crypto::sign(
                    &load_key(&directory.join("signing.key"))?,
                    &bytes("poll", &auth)?,
                ),
            };
            let r: Signed<Value> = post(
                &client()?,
                format!("{}/v1/poll", s.origin.trim_end_matches('/')),
                &p,
            )
            .await?;
            verify(&s.server_key, "poll-result", &r)?;
            ensure!(r.payload["nonce"] == auth.nonce, "nonce mismatch");
            println!("{}", serde_json::to_string_pretty(&r.payload["result"])?);
        }
        Commands::Backup {
            database,
            identity,
            passphrase_file,
            output,
        } => {
            let registry = Registry::open(&database, load_key(&identity)?)?;
            registry.check()?;
            let scratch = output.with_extension("snapshot.db");
            registry.backup(&scratch)?;
            let plain = zeroize::Zeroizing::new(serde_json::to_vec(
                &json!({"version":1,"database":crypto::encode(std::fs::read(&scratch)?),"identity":crypto::encode(std::fs::read(&identity)?)}),
            )?);
            std::fs::remove_file(scratch)?;
            let encryptor = age::Encryptor::with_user_passphrase(passphrase(&passphrase_file)?);
            let mut out = Vec::new();
            let mut writer = encryptor.wrap_output(&mut out)?;
            writer.write_all(&plain)?;
            writer.finish()?;
            create_private(&output, &out)?;
            println!("Encrypted registry and server identity backup written");
        }
        Commands::Restore {
            input,
            passphrase_file,
            directory,
        } => {
            let cipher = std::fs::read(input)?;
            ensure!(cipher.len() < 64 * 1024 * 1024, "oversized backup");
            let decryptor = age::Decryptor::new(&cipher[..])?;
            let identity = age::scrypt::Identity::new(passphrase(&passphrase_file)?);
            let mut plain = zeroize::Zeroizing::new(Vec::new());
            decryptor
                .decrypt(std::iter::once(&identity as &dyn age::Identity))?
                .take(64 * 1024 * 1024)
                .read_to_end(&mut plain)?;
            let v: Value = serde_json::from_slice(&plain)?;
            ensure!(v["version"] == 1, "unsupported backup");
            private_dir(&directory)?;
            create_private(
                &directory.join("registry.db"),
                &base64::engine::general_purpose::URL_SAFE_NO_PAD
                    .decode(v["database"].as_str().context("database missing")?)?,
            )?;
            create_private(
                &directory.join("server.key"),
                &crypto::decode(v["identity"].as_str().context("identity missing")?)?,
            )?;
            Registry::open(
                directory.join("registry.db"),
                load_key(&directory.join("server.key"))?,
            )?
            .check()?;
            create_private(&directory.join("QUARANTINED"),b"Review revocations made since this backup. Perform local Owner recovery and reconcile before deployment.\n")?;
            println!("Restored offline to quarantine; not activated");
        }
    }
    Ok(())
}
