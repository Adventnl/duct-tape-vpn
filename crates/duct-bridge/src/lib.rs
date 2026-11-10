//! Native-only crypto boundary. Secret inputs/outputs must never cross the Flutter method channel.
mod enrollment;
use anyhow::{Context, Result, ensure};
use duct_core::{crypto, protocol::*};
use serde_json::{Value, json};
use std::ffi::{CStr, CString, c_char};
fn field<'a>(v: &'a Value, name: &str) -> Result<&'a str> {
    v[name].as_str().context("missing field")
}
pub fn call(v: Value) -> Result<Value> {
    match field(&v, "op")? {
        "begin_enrollment" => enrollment::begin(&v),
        "finish_enrollment" => enrollment::finish(&v),
        "poll" => enrollment::poll(&v),
        "admin" => enrollment::admin(&v),
        "canonical" => {
            Ok(json!({"message":crypto::encode(bytes(field(&v,"domain")?,&v["payload"])?) }))
        }
        "keys" => {
            let signing = crypto::signing_key();
            let (private, public) = crypto::wg_keypair();
            Ok(
                json!({"signing_private":crypto::encode(signing.to_bytes()),"signing_key":crypto::public(&signing),"wireguard_private":crypto::encode(private),"wireguard_key":public}),
            )
        }
        "answer" => {
            let c: Signed<Challenge> = serde_json::from_value(v["challenge"].clone())?;
            let mut enrollment: Enrollment = serde_json::from_value(v["enrollment"].clone())?;
            let server = field(&v, "server_key")?;
            crypto::verify(server, &bytes("challenge", &c.payload)?, &c.signature)?;
            let expected_id = crypto::hash(crypto::decode(server)?);
            enrollment.invitation = crypto::hash(&enrollment.invitation);
            let now = v["now"].as_i64().context("time required")?;
            ensure!(
                c.payload.server_id == expected_id
                    && enrollment.server_id == expected_id
                    && c.payload.expires_at > now
                    && c.payload.expires_at <= now + 120
                    && c.payload.binding == crypto::hash(bytes("enrollment", &enrollment)?),
                "challenge binding mismatch"
            );
            let proof = String::from_utf8(crypto::open(
                &crypto::decode(field(&v, "wireguard_private")?)?,
                &c.payload.sealed,
                c.payload.binding.as_bytes(),
            )?)?;
            let key = p256::ecdsa::SigningKey::from_slice(&crypto::decode(field(
                &v,
                "signing_private",
            )?)?)?;
            ensure!(
                crypto::public(&key) == enrollment.signing_key,
                "signing identity mismatch"
            );
            let auth = Possession {
                challenge_id: c.payload.id.clone(),
                server_id: expected_id,
                binding: c.payload.binding.clone(),
                proof: proof.clone(),
            };
            Ok(
                json!({"claim":Claim{id:c.payload.id,proof,signature:crypto::sign(&key,&bytes("possession",&auth)?)},"fingerprint":c.payload.binding}),
            )
        }
        "verify" => {
            let r: Signed<Value> = serde_json::from_value(v["response"].clone())?;
            crypto::verify(
                field(&v, "server_key")?,
                &bytes(field(&v, "domain")?, &r.payload)?,
                &r.signature,
            )?;
            Ok(r.payload)
        }
        "sign" => {
            let key = p256::ecdsa::SigningKey::from_slice(&crypto::decode(field(
                &v,
                "signing_private",
            )?)?)?;
            Ok(json!({"signature":crypto::sign(&key,&bytes(field(&v,"domain")?,&v["payload"])?) }))
        }
        "server_id" => {
            Ok(json!({"server_id":crypto::hash(crypto::decode(field(&v,"server_key")?)?)}))
        }
        _ => anyhow::bail!("unsupported crypto operation"),
    }
}
/// # Safety
/// `input` must point to a NUL-terminated UTF-8 string, at most 32 KiB, alive for this call.
/// Caller must release the returned owned string with `duct_free` exactly once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn duct_call(input: *const c_char) -> *mut c_char {
    let out = std::panic::catch_unwind(|| {
        ensure!(!input.is_null(), "null input");
        let input = unsafe { CStr::from_ptr(input) };
        ensure!(input.to_bytes().len() <= 32768, "oversized input");
        let v: Value = serde_json::from_slice(input.to_bytes())?;
        call(v)
    });
    let value = match out {
        Ok(Ok(v)) => json!({"ok":v}),
        _ => json!({"error":"cryptographic operation rejected"}),
    };
    CString::new(value.to_string())
        .expect("JSON contains no NUL")
        .into_raw()
}
/// # Safety
/// `ptr` must be a live pointer returned by `duct_call` and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn duct_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        let mut owned = unsafe { CString::from_raw(ptr) }.into_bytes_with_nul();
        use zeroize::Zeroize;
        owned.zeroize();
    }
}
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_ducttape_vpn_Core_call(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    input: jni::objects::JString,
) -> jni::sys::jstring {
    let result = (|| -> Result<String> {
        let value: String = env.get_string(&input)?.into();
        ensure!(value.len() <= 32768, "oversized input");
        let out = call(serde_json::from_str(&value)?)?;
        Ok(json!({"ok":out}).to_string())
    })();
    let text =
        result.unwrap_or_else(|_| json!({"error":"cryptographic operation rejected"}).to_string());
    env.new_string(text)
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ffi_rejects_invalid_input() {
        let input = CString::new("{bad").unwrap();
        unsafe {
            let p = duct_call(input.as_ptr());
            let out = CStr::from_ptr(p).to_str().unwrap();
            assert!(out.contains("error"));
            duct_free(p);
        }
    }
    #[test]
    fn native_key_generation_roundtrip() {
        let keys = call(json!({"op":"keys"})).unwrap();
        let id = call(json!({"op":"server_id","server_key":keys["signing_key"]})).unwrap();
        assert_eq!(
            crypto::decode(id["server_id"].as_str().unwrap())
                .unwrap()
                .len(),
            32
        );
    }
}
