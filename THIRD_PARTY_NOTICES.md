Duct-Tape VPN source is licensed under Apache-2.0. The WireGuard name belongs to its respective owners; no affiliation is implied.

Runtime components have separate licenses:

| Component | Selected source/version | License | Integration |
|---|---|---|---|
| WireGuard Linux kernel/tools | distribution packages, version inspected before installation | GPL-2.0 kernel/tools; bundled components differ | Separate OS tools; never reimplement the protocol |
| WireGuardKit / Apple | `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1` | MIT | Linked native packet tunnel; retain upstream notices and Go module licenses |
| WireGuard Android tunnel | `1.0.20260102` from Maven Central | Apache-2.0 | Official GoBackend; retain AAR notices |
| WireGuard Windows tunnel service | `6ece77bc487c8aa697e3c092197621c4f3e5ccb8` source reference | MIT | Official embeddable service; no driver/DLL shipped here |
| WireGuardNT | separately obtained and verified official distribution | upstream license and notices required | Signed Windows driver; not built or redistributed by this task |
| Flutter / Dart | Flutter stable source `c197ca5199e9ee5661e865596c9c07294dfab51c` (`3.47.9`) | BSD-3-Clause and bundled notices | SDK artifacts currently blocked; not bundled |
| hpke / p256 / sha2 | exact versions in Cargo.lock | MIT/Apache-2.0 | RFC 9180 HPKE, P-256 ECDSA, SHA-256 |
| SQLite / rusqlite | Cargo.lock | public domain / MIT | Server registry only |
| age | Cargo.lock | MIT/Apache-2.0 | Passphrase-encrypted offline backups |
| tough | Cargo.lock | Apache-2.0 OR MIT | TUF verification, root rotation, metadata rollback and expiry |
| nlohmann/json | 3.12.0, SHA-256 pinned in CMakeLists.txt | MIT | Windows native plugin |
| Microsoft win32metadata | SDK GUID/constants used by MinGW compatibility header | MIT | Official WFP identifiers; no runtime implementation copied |
| qr_flutter / qr | constrained in pubspec.yaml; not resolved in this executor | BSD-3-Clause | Invitation QR rendering |

License copies for the WireGuard integrations are in `licenses/`. Before distributing a linked client or server, include the full license/notice files of every resolved bundled dependency and the generated Flutter license registry. `scripts/collect-rust-licenses.py` collects the exact downloaded Rust dependency notices for the unsigned Linux archive. This document does not replace those notices. Linux kernel, distribution packages, WireGuardNT, OS frameworks and Flutter SDK are not included in the unsigned server archive.

The unsigned development archive includes `rust-licenses/REQUIRES_NOTICE_REVIEW.json`. Six resolved packages did not publish a complete license/notice file at the expected source revision (bech32, cesu8, io_tee, two r-efi versions, typed-path). Their metadata/readmes are retained for review; this is an explicit public-redistribution blocker, not a license claim or permission waiver. Exact-commit supplemental notices recovered for other packages are under `licenses/rust-upstream/`.
