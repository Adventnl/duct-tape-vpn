BEGIN IMMEDIATE;
CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT;
CREATE TABLE devices(
 id TEXT PRIMARY KEY, name TEXT NOT NULL, platform TEXT NOT NULL CHECK(platform IN ('macos','windows','ios','android')),
 signing_key TEXT NOT NULL UNIQUE, wg_key TEXT NOT NULL UNIQUE,
 status TEXT NOT NULL CHECK(status IN ('pending','active','revoked','rejected')),
 slot INTEGER UNIQUE CHECK(slot BETWEEN 2 AND 251), revision INTEGER NOT NULL DEFAULT 0,
 fingerprint TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','client')),
 CHECK(role!='owner' OR platform='macos')
) STRICT;
CREATE UNIQUE INDEX sole_owner ON devices(role) WHERE role='owner';
CREATE TABLE invitations(id TEXT PRIMARY KEY,token_hash TEXT NOT NULL UNIQUE,expires_at INTEGER NOT NULL,state TEXT NOT NULL CHECK(state IN ('open','claimed','cancelled','expired'))) STRICT;
CREATE TABLE challenges(id TEXT PRIMARY KEY,enrollment TEXT NOT NULL,proof_hash TEXT NOT NULL,binding TEXT NOT NULL,expires_at INTEGER NOT NULL,invitation_hash TEXT NOT NULL) STRICT;
CREATE TABLE nonces(nonce TEXT PRIMARY KEY, expires_at INTEGER NOT NULL) STRICT;
CREATE TABLE approved_releases(version INTEGER PRIMARY KEY,sha256 TEXT NOT NULL) STRICT;
PRAGMA user_version=1;
COMMIT;
