# Protocol and threat model

The intended trust roots are the trusted Ubuntu console/SSH channel, the server signing public key deliberately imported through that channel, the Owner MacBook's separate P-256 administrative identity, platform TLS trust, and independent offline TUF root keys. An installer alone grants no access. Possession of an Owner invitation grants an opportunity to request approval. A trusted-console activation code preauthorizes one ordinary VPN client; neither path grants an Owner role.

## Enrollment v1

1. An authenticated Owner operation creates a 32-random-byte invitation token, valid for 30–900 seconds. SQLite stores SHA-256 of its base64url representation. QR/link payloads carry the public HTTPS origin, server signing key, token and expiry in a URI fragment. No token belongs in an HTTP URL, access log, crash report or analytics event.
2. The new device creates X25519/WireGuard and P-256 signing keys locally. The native bridge never sends a private key to Dart or the server.
3. The device sends its invitation, name, platform and both public keys to `/v1/challenge` over validated HTTPS. The registry checks bounds and availability without claiming the invitation.
4. The server signs a 120-second challenge. Its binding is SHA-256 of the enrollment transcript, containing the server identity, hashed invitation, platform/name and both device keys. It seals a fresh 256-bit proof to the candidate's X25519 key using RFC 9180 HPKE (X25519/HKDF-SHA256/ChaCha20Poly1305), with the binding as associated data. Low-order/invalid DH is rejected by the vetted implementation.
5. The device verifies the server signature, identity, transcript and expiry, decrypts with its WireGuard private key, and signs a domain-separated possession transcript using its independent P-256 key. It securely checkpoints the request before claiming, so a lost response can be recovered by signed polling.
6. Claiming atomically consumes the still-open invitation and creates a pending Client. All sibling challenges are removed. Replays fail. Pending devices are excluded from the helper's peer set.
7. Both devices show the same full 256-bit fingerprint. The Owner must compare the complete value through a trusted path. Approval binds the exact pending ID and fingerprint to a signed operation. Only then is a unique address allocated and peer provisioning requested.
8. A nonce-bound device-signed poll obtains server-signed public configuration after reconciliation. It never returns the device private key. Endpoint changes retain the server signing/WireGuard identity and require no reenrollment. Automatic out-of-tunnel endpoint discovery is not implemented; deliberate refresh/import is required when the old endpoint is unreachable.

WireGuard keys use unpadded base64url in the application protocol and canonical padded base64 only at WireGuard tooling boundaries. P-256 public keys are canonical uncompressed SEC1; signatures are 64-byte IEEE-P1363 r||s. Signed messages are UTF-8 `duct-tape/<domain>/v1\n` followed by JSON with recursively sorted object keys and compact serialization. Protocol fields use integer timestamps and bounded strings; no floating-point fields are signed. This is a specified v1 encoding, not an assertion of general-purpose RFC 8785 canonicalization. TLS still validates normally; application identity pinning supplements it.

## Server-issued activation

`ductctl generate` (also packaged as `dvpn generate`) runs on the trusted server
console. It creates an 80-bit random, five-minute, single-use code. Only hashes
persist in the registry. `/v1/activate` resolves a previously issued code over
certificate-validated HTTPS and cannot create codes. Because the short code has
no signing-key pin, the user-entered HTTPS origin and platform/WebPKI TLS trust
establish the first server identity; subsequent challenge, claim and poll messages
pin its signing key. The code must be transferred privately.

The usual dual-key possession challenge still applies. A successful claim of an
activation invitation atomically consumes it, allocates an address and authorizes
a Client. Configuration is withheld until the helper applies that revision.
Legacy Owner invitations still create pending clients requiring fingerprint
approval. Recovery cancels both kinds of invitation; revocation works for both.
No public API can issue codes or promote an ordinary client.

## Owner and recovery

Admin authorization binds server identity, a 32-byte nonce, expiry at most 60 seconds ahead and the complete typed operation. The server verifies the active sole Owner public key, never a role supplied by a client. Nonces are consumed transactionally and retained through expiry. Replay, altered operations and ordinary client signatures fail. Public routes cannot promote a device. Only the trusted-local recovery CLI can replace the Owner key/peer and invalidate outstanding invitations.

The Mac Owner identity is a distinct Secure Enclave P-256 key protected by user presence. Each sensitive signing operation uses a fresh LAContext. Devices without supported Secure Enclave hardware fail this path; no silent software downgrade is implemented. Ordinary platform signing/WireGuard keys use OS-protected storage. A trusted console CLI also supports software fixture/administration keys for development; these do not establish hardware-backed production Owner readiness.

## Network protection and limits

Default peer routing is IPv4 0/0 and IPv6 ::/0 with DNS at the private home resolver and MTU 1280. The first server policy deliberately drops tunneled IPv6 forwarding rather than providing partial IPv6 internet service. Server input from VPN devices is limited to owned DNS/private administration ingress; private/LAN destinations are denied by default. No trusted-network bypass is enabled. SSIDs never authenticate a network.

Apple includeAllNetworks/enforceRoutes have system exceptions; the UI reports limited protection. On Android, OS Always-on plus “Block connections without VPN” must be configured by the user for process-crash blocking. The ordinary VPN permission alone is insufficient. The Windows persistent WFP policy is designed to retain blocking across crashes and to permit only loopback, the tunnel interface and the fixed WireGuard transport tuple/process; it has not been runtime-certified. Boot-time filtering and concurrent existing socket behavior need explicit Windows tests. Never infer protection from a process, port or handshake.

There is no verified home-exit/DNS attestation pipeline yet. Native adapters do not supply `verifiedAt`, so production UI cannot show Protected. Subnet overlap detection, safe configurable address-pool migration, LAN endpoint authentication, automatic pin rotation and robust endpoint-change recovery remain engineering work; they must be validated before this becomes an everyday VPN.

## Availability and privilege boundaries

Bodies are bounded to 8 KiB, helper input to 64 KiB, challenges to 256 globally/eight per invitation, open invitations to 128, helper peers to 250. The public gateway limits concurrent forwards to 32 and has an eight-second timeout. The required TLS ingress template adds per-source rate limits and no body/access logging. Do not expose the unrate-limited loopback gateway directly. Retention cleanup/quota for historic rejected devices and spent invitations still needs operational hardening; public load testing is outstanding.

Threats covered by tests include races, replay, key substitution, client-to-Owner escalation, stale/incorrect fingerprints, expired invitations, malformed helper requests, persistent revocation, identity mismatch and future database schemas. Compromised root/admin OS, physical capture of an unlocked Owner, a malicious paired device's own traffic and denial of service against the home uplink are outside this trust boundary. No browsing history or telemetry is collected.
