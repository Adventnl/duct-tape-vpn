# Acceptance matrix

Record OS/build/device, server commit/packages, endpoint type, underlying IPv4/IPv6 network and exact observations. Run only against an explicitly approved deployment. A handshake alone is never a pass.

| Scenario | Required evidence | Current result |
|---|---|---|
| Local bootstrap | Sole macOS Owner row; separate admin/WireGuard keys; wrong identity rejected | Rust tests pass; hardware path unrun |
| Remote pairing | TLS + pinned identity; 256-bit one-use invitation; key possession; pending peer has no access | Real local HTTP gateway/registry + HPKE test pass; production HTTPS ingress unrun |
| Owner approval | Independently compared fingerprint; operation-bound fresh signature | Rust tests pass; SE/user-presence unrun |
| ON / full IPv4 exit | New and existing TCP/UDP flows exit via home's externally observed address; no underlay egress except transport | Unrun: no home access or kernel/TUN in executor |
| Home DNS | Normal and negative queries use only private Unbound; TLS upstream identity validated; DNSSEC bogus queries fail; upstream loss has no UDP/plaintext fallback | Configuration provided; traffic/DoT/DNSSEC unrun |
| IPv6 | Dual-stack underlay probes cannot leave directly; v1 tunneled IPv6 is blocked at server | Policy source provided; unrun |
| Transport loops | WireGuard UDP stays on physical underlay; DNS/endpoint refresh does not recurse into broken tunnel | Source design only; unrun |
| Window close/reopen | Continuous remote stream + capture; same native service/tunnel; truthful status after reopen | Unrun on all four OSs |
| UI crash | Tunnel/protection remain; desired ON survives | Source lifecycle exists; unrun |
| Tunnel/service crash | Traffic blocked at strongest supported level; bounded retries retain ON; explicit OS exceptions recorded | State tests pass; native traffic unrun |
| Roam, wake, reboot | ON preference restored, no unintended direct traffic before tunnel, cancellation by OFF | Source lifecycle partial; unrun |
| Revocation | Registry change persists; helper removes peer; existing traffic stops; no reappearance after restart | Registry/persistence pass; kernel removal unrun |
| Intentional OFF | Tunnel stopped; owned protection removed only on OFF; ordinary IPv4/IPv6/DNS return; unrelated rules unchanged | Lab baseline routing passed; native restoration unrun |
| Subnet collision | Existing LAN/VPN routes never silently weaken protection; supported pool migration or explicit refusal | Engineering outstanding |
| Malformed/replayed input | Reject oversized, wrong-key, expired, raced, substituted operations; no peer privilege | Rust/security + gateway tests pass |
| Backup/restore | Encrypted round trip preserves identity/registry; restore remains offline; stale revocations reviewed | Real CLI round trip passes |
| Updates | Pinned TUF root, expiry/hash/signature/rollback/compatibility + separate Owner approval | Nine HTTPS fixture checks pass; real release/install unrun |
| Deployment | Reviewed host inspection, backups, idempotent owned changes, health and rollback; SSH/other services preserved | File-staging tests pass; Ubuntu deployment unrun |
| UI accessibility | Real Flutter screenshots at desktop/mobile scales, keyboard, screen readers, dark and reduced motion | Concept renders inspected; Dart syntax parsed; Flutter/device checks blocked |

The disposable lab first validates ordinary namespace routing. This executor reached that check, then rejected kernel WireGuard creation (`Unknown device type`). Official userspace fallback was also blocked because TUN-device creation is not permitted. No lab NAT, tunneled DNS, kill-switch, reconnect or OFF-restoration result is claimed. Run the lab on a suitable isolated Linux host, then test each native implementation independently: the lab filter is not the native OS filter.

For real-device tests, capture on both the underlay and the home exit with consent and minimal retention; never collect browsing history. Use a controlled external HTTPS/UDP test target and a home-side observation to compare exit address. Probe IPv4, IPv6, DNS TCP/UDP, QUIC and existing sockets during transitions. Test endpoint failure, private subnet overlap, unreachable DoT upstream, helper restart, registry/gateway shutdown and revocation while management services are unhealthy. Restore ordinary networking and confirm SSH/other home services after each approved network change.
