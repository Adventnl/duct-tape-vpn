#pragma once
#include <nlohmann/json.hpp>

// Only the administrator-installed personal profile is checked here.
// A passing connection check makes no claim about failure blocking or IPv6.
nlohmann::json ManagedConnectionSnapshot(bool running, unsigned long processId);
void ResetManagedConnectionCheck();
