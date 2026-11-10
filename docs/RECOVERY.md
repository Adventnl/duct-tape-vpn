# Owner recovery and encrypted backups

The Owner's administrative signing key is distinct from its WireGuard key. The production Mac path generates it in Secure Enclave with Keychain/user-presence protection; it cannot be exported or backed up as a portable private key. Losing that Mac requires trusted local server recovery, not an invitation or a cloud account.

From a trusted Ubuntu console/SSH session, obtain replacement Mac public keys and make an encrypted backup first. Then:

```sh
ductctl recover --database /var/lib/dtvpn/registry.db \
  --identity /var/lib/dtvpn/server.key --owner-public REPLACEMENT_MAC_PUBLIC.json
```

Recovery replaces the sole Owner signing identity and WireGuard peer atomically, cancels every invitation, removes unclaimed challenges and advances the desired peer-set revision. Old administrative signatures are rejected immediately. The helper must successfully reconcile before the old Owner's WireGuard access is gone. Stop exposure or reconcile locally if it is unavailable; do not report removal based on a registry acknowledgement alone. Ordinary clients are retained. Generate and deliberately import a replacement signed Owner bundle via the trusted local channel. No remote endpoint promotes a Client to Owner.

## Backup

Use a securely created mode-0600 passphrase file with a strong, unique passphrase of at least 20 characters, stored separately from the backup. Never enter it in chat, shell command arguments, CI or source. A password-manager export to a private temporary file is appropriate; remove that file when finished.

```sh
umask 077
ductctl backup --database /var/lib/dtvpn/registry.db \
  --identity /var/lib/dtvpn/server.key \
  --passphrase-file /PRIVATE/TEMP/PASSPHRASE \
  --output /PRIVATE/BACKUPS/registry-identity.age
```

SQLite's online backup captures a consistent database including WAL state. The CLI combines that snapshot with the separate server signing identity in an age passphrase-encrypted envelope. The temporary snapshot is created with mode 0600 and removed before the encrypted artifact is written. The backup does not contain device private keys, nonexportable Owner SE material, the separate root-owned server WireGuard key, TLS certificates, router configuration or shared host firewall state. Back those up separately using established encrypted system backup tooling. A registry-only backup cannot reconstruct the server's WireGuard identity.

## Restore rehearsal

```sh
ductctl restore --input /PRIVATE/BACKUPS/registry-identity.age \
  --passphrase-file /PRIVATE/TEMP/PASSPHRASE \
  --directory /NEW/OFFLINE/RESTORE-DIRECTORY
```

The destination must not exist. Decryption, schema compatibility, database integrity and the signing-key/server-ID binding are checked. The CLI writes a QUARANTINED marker and does not activate services or restore peers. Do not activate a stale registry blindly: it can resurrect devices revoked after the backup. Review the retained registry, recover the Owner locally, repeat post-backup revocations and invalidate old invitations before reconciling. Preserve a current backup before replacing active state. Moving a reviewed restore into service state is a separate deployment action.

The real-process smoke test generates an encrypted backup, restores it to a new offline directory, checks quarantine and verifies registry integrity/identity. Hardware key recovery and complete home-server disaster recovery have not been exercised.

## Deliberate identity rotation

A changed server signing key is always rejected by an already pinned client. There is no silent trust-on-first-use reset. Until a dual-signed rotation protocol is implemented and certified, rotate through a trusted local maintenance session: back up, disconnect/secure deployment, update the server identity and corresponding registry binding under a reviewed migration, then explicitly import the new pin/configuration on every device. Such a migration is not supplied as an automatic command. Endpoint/DDNS changes retain the existing signing key and do not need this procedure.
