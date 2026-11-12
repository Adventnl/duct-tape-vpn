# Duct-Tape VPN

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

The owner connects personal devices to their Ubuntu server. This session prioritizes a Windows PC and a mobile layout.

## Product purpose

A personal WireGuard VPN with the owner's server as its exit. Success requires an actual tunnel and traffic checks, independently of the interface's requested connection state.

## Capabilities and constraints

The existing Flutter client targets Windows, Android, iOS and macOS. Rust owns enrollment and server operations. Existing native adapters and platform protection claims require verification. Do not label a requested or merely running tunnel as Protected.

## Brand commitments

The user supplied an Apple design reference and requested a complete mobile UI replacement with simple controls and restrained translucent glass. Preserve the Duct-Tape VPN name.

## Operating context

Link Tunnel reaches hanoryx-server. Existing UFW and Tailscale networking must be preserved. Keys and device configuration stay outside source control and chat output.

## Confirmed scope

The user confirmed duct-tape-vpn as the target repository. Rebuild the mobile interface and configure a working connection from this Windows PC to hanoryx-server.

## Evidence on hand

README.md, docs/STATUS.md and the native platform source record the current implementation boundaries. Platform source is not proof of a working installation.
