# Signed updates

`duct-update` stages a target only after the maintained `tough` TUF client validates it. It does not install it or restart anything. Trust begins with a separately distributed offline root, not a key fetched alongside the update. There is deliberately no default production root, online signing secret, release feed or installation backdoor in this repository.

The verifier keeps a persistent datastore, enforces metadata expiry, signature thresholds, root transitions, metadata versions and target hashes/lengths. A per-platform signed manifest identifies artifact/version, protocol compatibility, SHA-256 and exact length. Metadata lengths are checked before loading the manifest/artifact. The manifest is bounded to 16 KiB, the artifact to 512 MiB. It rejects a version no newer than the installed version supplied by the platform installer.

In addition, the Owner must approve the artifact's SHA-256 and version through an operation-bound admin signature. The server returns a server-signed approval only after Owner verification and records the version/hash binding. A version cannot be rebound to a different hash. `duct-update` checks that approval against the pinned server key. Client release approval and server deployment approval are separate: staged client bytes never authorize changing the server or host network.

Example after a real offline-root ceremony, platform build, signing and Owner review:

```sh
duct-update --root /PROTECTED/trusted-root.json \
 --metadata-url https://YOUR_FEED/metadata/ --targets-url https://YOUR_FEED/targets/ \
 --cache /PROTECTED/PERSISTENT/tuf-state --approval /PRIVATE/owner-release-approval.json \
 --server-key PINNED_SERVER_PUBLIC_BASE64URL --platform macos-arm64 \
 --current-version INSTALLED_MONOTONIC_INTEGER --output /PRIVATE/STAGED/verified-package
```

The current-version input must come from trusted installed product state. Never reset the TUF cache or lie about installed version to force an update. Uninstall/reinstall trust-reset behavior, authenticated installer receipt storage and client GUI integration remain to be implemented. A staged file is not an installed update.

Production release work still requires:

- Offline independent root keys and threshold/expiry/rotation policy; keep them out of CI. Use established TUF publishing tooling and separate targets/snapshot/timestamp roles with scoped keys.
- Valid macOS Developer ID/notarization or App Store path; matching Network Extension/Keychain provisioning. Legitimate iOS distribution/profiles and an entitled app/extension. No Developer Mode bypass substitutes for entitlements.
- Windows Authenticode signing and verified official WireGuardNT binaries. The prepared installer refuses unsigned/unverified service DLLs; the cross-built diagnostic executable is not an installable signed release.
- Android release signing and appropriate distribution, foreground-service declaration and user-configured lockdown behavior. An unsigned/debug APK is not a verified release.
- Ubuntu package/service artifact signing, dependencies and a separately approved deployment plan.

Nine HTTPS-fixture checks passed: valid staging, installed-version rollback rejection, persistent metadata advance/rollback, corrupt artifact rejection, invalid metadata signature, expired timestamp, altered Owner approval and protocol incompatibility. These fixture keys never become production trust anchors. Production publication, independent root rotation ceremonies, platform installers and end-to-end update installation remain unverified.
