#pragma once
#include <nlohmann/json.hpp>
#include <optional>

// This adapter controls only the fixed, administrator-installed official tunnel.
// It never accepts executable paths, configurations, or commands from Dart.
std::optional<nlohmann::json> ManagedTunnelSnapshot();
bool ManagedTunnelSetDesired(bool on);
