# Implementation plan

1. Build and exercise the Rust enrollment registry: local Owner bootstrap, HPKE proof of WireGuard key possession, independent P-256 signing identity, atomic invitations, operation-bound Owner authorization, revocation and persistent reconciliation.
2. Separate the public HTTPS gateway, private administration, registry and privileged WireGuard operations. Prepare inspection-first deployment with owned resources and explicit change approval.
3. Build the shared Flutter presentation and state model, enrollment transport and native service bridges. Use WireGuardKit, Android's official tunnel library and Windows' official tunnel service. Never infer protection from UI intent or a handshake.
4. Add recovery/backup, update verification, packaging, isolated tests and platform validation instructions. Record incomplete integration and external blockers precisely.

## Validation boundaries

This checkout started at 837e905 with only README.md. The attached executor is Debian Linux, not the home Ubuntu host. No home-server access or platform signing identity is supplied. No deployment or host firewall changes are authorized as routine setup. Never substitute a mock result for a device or traffic test.

Required local checks: Rust compilation, security and persistence tests, malformed input tests, helper bounds, Flutter analysis/widget tests if artifacts can be fetched, deployment plan/rollback tests. Required external acceptance: real home exit/DNS, IPv6 blocking, service/UI crashes, reboot, roaming, intentional OFF on each supported OS. Signing and release publication require legitimate credentials and entitlement provisioning.
