# Android installation and server-issued activation

Install the personal development APK on Android 8 (API 26) or later. It contains
native libraries for arm64-v8a, armeabi-v7a and x86_64. This build uses a local
development signing key, not a production distribution identity.

On a server already running the registry/helper deployment, first issue a code
with the externally reachable, certificate-valid HTTPS enrollment origin:

```sh
sudo dvpn generate --origin https://vpn.example.org
```

The Linux package includes `dvpn` as an alias of `ductctl`. Install that alias on
the server command path, for example with
`sudo ln -s /usr/local/lib/duct-tape-vpn/ductctl /usr/local/bin/dvpn`
after verifying that destination is unused. Existing installations
can use `sudo /usr/local/lib/duct-tape-vpn/ductctl generate --origin https://vpn.example.org`.
The default identity/database paths are `/var/lib/dtvpn/server.key` and
`/var/lib/dtvpn/registry.db`; override them for a different inspected installation.
The origin is remembered in that database, so subsequent runs need only:

```sh
sudo dvpn generate
```

Personal APKs can include the enrollment origin at build time:

```sh
DUCT_ACTIVATION_ORIGIN=https://vpn.example.org scripts/build-android.sh
```

On the phone, tap **Set up connection**, enter the generated activation code in
the single field, and tap **Activate device**. Builds without this setting also
ask for the server address and support Owner invitation links.
Configuration is saved in Android Keystore-
encrypted storage. Once provisioning finishes, return to VPN and tap **Connect**.
No second Owner approval is required for a server-issued activation code.

The five groups of four hexadecimal characters contain 80 random bits. Codes
expire after five minutes and authorize one ordinary client. A code cannot grant
Owner/admin access. Keep it private: whoever redeems it first gets that client
connection. Only the trusted server console can issue these codes. The phone
redeems an existing code; it cannot request a new code or authorize itself.
Its WireGuard and signing private keys are generated locally and never uploaded.

An independent server address is necessary to locate the server without a lookup
service; personal builds supply it through `DUCT_ACTIVATION_ORIGIN` instead of
asking the user. This is a public HTTPS origin, never a code or private key.
The initial identity is authenticated through normal HTTPS certificate
validation at that address; subsequent protocol messages pin the signing key.
Existing Owner-issued invitation links retain fingerprint approval.

## Server update

Update **both** `duct-registry` and `duct-gateway`, and add `/v1/activate` to the
existing TLS ingress route allowlist, as in
`deploy/templates/nginx-enrollment.conf.example`. Preserve its rate limits and
no access/body logging. The registry automatically migrates schema v1/v2 to v3.
Back up the database/identity before deployment; older server binaries refuse v3.
No public endpoint creates an activation code.

The separately documented `personal-server.py` WireGuard setup has no registry,
TLS enrollment listener, or reconciliation helper. Installing this APK alone does
not upgrade that server. Do not point the registry helper at that existing tunnel:
reconciliation owns its entire peer set. Use the trusted-console `bootstrap --existing-peers` migration described in
[deployment](DEPLOYMENT.md) to retain existing Windows/Mac peer addresses. The
network, forwarding, DNS and HTTPS ingress still require host-specific inspection.

## Connection checks and device validation

Android checks HTTPS with normal DNS/certificate validation, binding the probe to
the VPN network with this device's assigned tunnel address. It also requires
increasing received WireGuard bytes and a handshake within three minutes.
The UI expires successful checks after 30 seconds. These are connection checks,
not exit-identity or leak-protection certification. The app reports limited
protection. Enable Android's Always-on VPN and **Block connections without VPN**
in system settings for OS crash blocking.

Validate activation and Connect/Disconnect on a physical phone against the real
server, including mobile data, Wi-Fi changes, reboot and background operation.
Build/emulator checks do not establish real home-exit reachability.
