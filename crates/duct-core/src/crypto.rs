use anyhow::{Result, bail, ensure};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use hpke::{
    Deserializable, Kem, OpModeR, OpModeS, Serializable, aead::ChaCha20Poly1305, kdf::HkdfSha256,
    kem::X25519HkdfSha256,
};
use p256::ecdsa::{
    Signature, SigningKey, VerifyingKey,
    signature::{Signer, Verifier},
};
use rand::{RngCore, rngs::OsRng};
use rand09::SeedableRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub fn encode(b: impl AsRef<[u8]>) -> String {
    URL_SAFE_NO_PAD.encode(b)
}
pub fn decode(s: &str) -> Result<Vec<u8>> {
    ensure!(s.len() <= 4096, "oversized encoding");
    Ok(URL_SAFE_NO_PAD.decode(s)?)
}
pub fn random() -> String {
    let mut b = [0; 32];
    OsRng.fill_bytes(&mut b);
    encode(b)
}
pub fn hash(b: impl AsRef<[u8]>) -> String {
    encode(Sha256::digest(b))
}
pub fn signing_key() -> SigningKey {
    SigningKey::random(&mut OsRng)
}
pub fn public(k: &SigningKey) -> String {
    encode(k.verifying_key().to_encoded_point(false).as_bytes())
}
pub fn verify(key: &str, message: &[u8], signature: &str) -> Result<()> {
    let key = VerifyingKey::from_sec1_bytes(&decode(key)?)?;
    let signature = Signature::from_slice(&decode(signature)?)?;
    key.verify(message, &signature)?;
    Ok(())
}
pub fn sign(key: &SigningKey, message: &[u8]) -> String {
    let s: Signature = key.sign(message);
    encode(s.to_bytes())
}
pub fn signing_public_valid(key: &str) -> Result<()> {
    let decoded = decode(key)?;
    let vk = VerifyingKey::from_sec1_bytes(&decoded)?;
    ensure!(
        vk.to_encoded_point(false).as_bytes() == decoded,
        "non-canonical signing key"
    );
    Ok(())
}
pub fn wg_public_valid(key: &str) -> Result<()> {
    let b = decode(key)?;
    ensure!(
        b.len() == 32 && b.iter().any(|x| *x != 0),
        "invalid WireGuard key"
    );
    Ok(())
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Sealed {
    pub encapsulated: String,
    pub ciphertext: String,
}
const INFO: &[u8] = b"duct-tape/enrollment-key-possession/v1";
pub fn seal(wg_public: &str, plaintext: &[u8], aad: &[u8]) -> Result<Sealed> {
    type K = X25519HkdfSha256;
    let pk = <K as Kem>::PublicKey::from_bytes(&decode(wg_public)?)?;
    let (enc, mut ctx) = hpke::setup_sender::<ChaCha20Poly1305, HkdfSha256, K, _>(
        &OpModeS::Base,
        &pk,
        INFO,
        &mut rand09::rngs::StdRng::from_os_rng(),
    )?;
    Ok(Sealed {
        encapsulated: encode(enc.to_bytes()),
        ciphertext: encode(ctx.seal(plaintext, aad)?),
    })
}
pub fn open(wg_private: &[u8], sealed: &Sealed, aad: &[u8]) -> Result<Vec<u8>> {
    type K = X25519HkdfSha256;
    let sk = <K as Kem>::PrivateKey::from_bytes(wg_private)?;
    let enc = <K as Kem>::EncappedKey::from_bytes(&decode(&sealed.encapsulated)?)?;
    let mut ctx =
        hpke::setup_receiver::<ChaCha20Poly1305, HkdfSha256, K>(&OpModeR::Base, &sk, &enc, INFO)?;
    Ok(ctx.open(&decode(&sealed.ciphertext)?, aad)?)
}
pub fn wg_keypair() -> (Vec<u8>, String) {
    let (sk, pk) = X25519HkdfSha256::gen_keypair(&mut rand09::rngs::StdRng::from_os_rng());
    (sk.to_bytes().to_vec(), encode(pk.to_bytes()))
}
pub fn constant_eq(a: &str, b: &str) -> bool {
    use subtle::ConstantTimeEq;
    a.as_bytes().ct_eq(b.as_bytes()).into()
}
pub fn validate_name(s: &str) -> Result<()> {
    if s.trim() != s || s.is_empty() || s.len() > 80 || s.chars().any(|c| c.is_control()) {
        bail!("invalid device name")
    };
    Ok(())
}
