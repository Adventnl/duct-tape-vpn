#include "managed_tunnel.h"
#include "connection_check.h"
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <stdexcept>

namespace {
constexpr wchar_t serviceName[] = L"WireGuardTunnel$DuctTape";
struct Handle {
  SC_HANDLE value;
  ~Handle() { if (value) CloseServiceHandle(value); }
};

std::wstring ProgramFiles() {
  PWSTR raw = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFiles, 0, nullptr, &raw)))
    throw std::runtime_error("Program Files unavailable");
  std::wstring result(raw);
  CoTaskMemFree(raw);
  return result;
}

SC_HANDLE OpenTunnel(DWORD access) {
  Handle manager{OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT)};
  if (!manager.value) throw std::runtime_error("SCM unavailable");
  Handle service{OpenServiceW(manager.value, serviceName, SERVICE_QUERY_CONFIG | access)};
  if (!service.value) {
    if (GetLastError() == ERROR_SERVICE_DOES_NOT_EXIST) return nullptr;
    throw std::runtime_error("Tunnel service access denied");
  }
  DWORD required = 0;
  QueryServiceConfigW(service.value, nullptr, 0, &required);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || required > 65536)
    throw std::runtime_error("Tunnel service configuration unavailable");
  std::vector<BYTE> storage(required);
  auto config = reinterpret_cast<QUERY_SERVICE_CONFIGW*>(storage.data());
  if (!QueryServiceConfigW(service.value, config, required, &required))
    throw std::runtime_error("Tunnel service configuration unavailable");
  int count = 0;
  auto args = CommandLineToArgvW(config->lpBinaryPathName, &count);
  const auto root = ProgramFiles();
  const bool valid = args && count == 3 &&
    _wcsicmp(args[0], (root + L"\\WireGuard\\wireguard.exe").c_str()) == 0 &&
    _wcsicmp(args[1], L"/tunnelservice") == 0 &&
    _wcsicmp(args[2], (root + L"\\DuctTapeVPN\\DuctTape.conf").c_str()) == 0 &&
    _wcsicmp(config->lpServiceStartName, L"LocalSystem") == 0;
  if (args) LocalFree(args);
  if (!valid) throw std::runtime_error("Unexpected tunnel service configuration");
  SC_HANDLE result = service.value;
  service.value = nullptr;
  return result;
}
}

std::optional<nlohmann::json> ManagedTunnelSnapshot() {
  Handle service{OpenTunnel(SERVICE_QUERY_STATUS)};
  if (!service.value) return std::nullopt;
  SERVICE_STATUS_PROCESS status{};
  DWORD length = 0;
  if (!QueryServiceStatusEx(service.value, SC_STATUS_PROCESS_INFO,
      reinterpret_cast<BYTE*>(&status), sizeof(status), &length))
    throw std::runtime_error("Tunnel state unavailable");
  const bool up = status.dwCurrentState == SERVICE_RUNNING;
  const bool starting = status.dwCurrentState == SERVICE_START_PENDING;
  auto result = ManagedConnectionSnapshot(up, status.dwProcessId);
  result.update(nlohmann::json{{"desired", up || starting ? "on" : "off"},
    {"tunnel", up ? "up" : starting ? "connecting" : "down"},
    {"protection", up ? "limited" : "none"}});
  return result;
}

bool ManagedTunnelSetDesired(bool on) {
  Handle service{OpenTunnel(on ? SERVICE_START : SERVICE_STOP)};
  if (!service.value) return false;
  SERVICE_STATUS status{};
  if (on) {
    if (!StartServiceW(service.value, 0, nullptr) && GetLastError() != ERROR_SERVICE_ALREADY_RUNNING)
      throw std::runtime_error("Tunnel could not start");
  } else if (!ControlService(service.value, SERVICE_CONTROL_STOP, &status) &&
      GetLastError() != ERROR_SERVICE_NOT_ACTIVE) {
    throw std::runtime_error("Tunnel could not stop");
  }
  ResetManagedConnectionCheck();
  return true;
}
