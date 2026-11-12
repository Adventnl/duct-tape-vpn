#include "connection_check.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windns.h>
#include <winhttp.h>
#include <chrono>
#include <future>
#include <string>
#include <vector>

namespace {
using Clock = std::chrono::steady_clock;
using namespace std::chrono_literals;
constexpr auto checkTimeout = 15s;
constexpr auto checkInterval = 10s;
constexpr auto evidenceLifetime = 30s;

SOCKADDR_INET Address(const wchar_t* text) {
  SOCKADDR_INET result{};
  result.si_family = AF_INET;
  InetPtonW(AF_INET, text, &result.Ipv4.sin_addr);
  return result;
}

bool RoutesUseTunnel() {
  NET_LUID tunnel{};
  if (ConvertInterfaceAliasToLuid(L"DuctTape", &tunnel) != NO_ERROR) return false;
  const auto expected = Address(L"10.77.0.2");
  for (auto target : {L"10.77.0.1", L"1.1.1.1"}) {
    const auto destination = Address(target);
    MIB_IPFORWARD_ROW2 route{};
    SOCKADDR_INET source{};
    // No interface constraint: inspect the route Windows would actually select.
    if (GetBestRoute2(nullptr, 0, nullptr, &destination, 0, &route, &source) != NO_ERROR ||
        route.InterfaceLuid.Value != tunnel.Value || source.si_family != AF_INET ||
        source.Ipv4.sin_addr.S_un.S_addr != expected.Ipv4.sin_addr.S_un.S_addr)
      return false;
  }
  return true;
}

bool HomeResponds() {
  auto handle = IcmpCreateFile();
  if (handle == INVALID_HANDLE_VALUE) return false;
  char payload[] = "DuctTape connection check";
  std::vector<BYTE> reply(sizeof(ICMP_ECHO_REPLY) + sizeof(payload) + 8);
  const auto home = Address(L"10.77.0.1");
  const auto count = IcmpSendEcho(handle, home.Ipv4.sin_addr.S_un.S_addr,
      payload, sizeof(payload), nullptr, reply.data(), static_cast<DWORD>(reply.size()), 1500);
  const bool passed = count > 0 &&
      reinterpret_cast<ICMP_ECHO_REPLY*>(reply.data())->Status == IP_SUCCESS;
  IcmpCloseHandle(handle);
  return passed;
}

bool DnsResponds() {
  PDNS_RECORDW records = nullptr;
  const auto status = DnsQuery_W(L"example.com", DNS_TYPE_A,
      DNS_QUERY_BYPASS_CACHE | DNS_QUERY_WIRE_ONLY, nullptr, &records, nullptr);
  bool passed = false;
  if (status == ERROR_SUCCESS) {
    for (auto record = records; record; record = record->pNext)
      passed = passed || record->wType == DNS_TYPE_A;
  }
  if (records) DnsRecordListFree(records, DnsFreeRecordList);
  return passed;
}

struct HttpHandle {
  HINTERNET value;
  ~HttpHandle() { if (value) WinHttpCloseHandle(value); }
};

bool InternetResponds() {
  // A fixed IPv4 target matches the personal server's IPv4 egress support.
  // Use system TLS validation, no proxy, no credentials, and no redirects.
  HttpHandle session{WinHttpOpen(L"DuctTapeVPN/connection-check",
      WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)};
  if (!session.value || !WinHttpSetTimeouts(session.value, 2000, 2500, 2500, 2500)) return false;
  HttpHandle connection{WinHttpConnect(session.value, L"1.1.1.1", INTERNET_DEFAULT_HTTPS_PORT, 0)};
  if (!connection.value) return false;
  HttpHandle request{WinHttpOpenRequest(connection.value, L"GET", L"/cdn-cgi/trace",
      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE | WINHTTP_FLAG_REFRESH)};
  if (!request.value) return false;
  DWORD disabled = WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_AUTHENTICATION;
  if (!WinHttpSetOption(request.value, WINHTTP_OPTION_DISABLE_FEATURE, &disabled, sizeof(disabled)) ||
      !WinHttpSendRequest(request.value, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
          WINHTTP_NO_REQUEST_DATA, 0, 0, 0) || !WinHttpReceiveResponse(request.value, nullptr))
    return false;
  DWORD status = 0, length = sizeof(status);
  if (!WinHttpQueryHeaders(request.value, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX) || status != 200)
    return false;
  // Bound the response. Neither the exit IP nor the trace is retained or logged.
  std::string body;
  while (body.size() < 4096) {
    char buffer[1024]{};
    DWORD received = 0;
    if (!WinHttpReadData(request.value, buffer, sizeof(buffer), &received) || received == 0) break;
    body.append(buffer, received);
    if (body.find("\nip=") != std::string::npos && body.find("\ntls=") != std::string::npos) return true;
  }
  return false;
}

std::string CheckConnection() {
  if (!RoutesUseTunnel()) return "Internet traffic is not using the VPN. Disconnect and try again.";
  if (!HomeResponds()) return "Your home server did not respond. Check the server and try again.";
  if (!DnsResponds()) return "DNS did not respond through the connection. Disconnect and try again.";
  if (!InternetResponds()) return "The VPN could not reach the internet. Disconnect and try again.";
  if (!RoutesUseTunnel()) return "The VPN route changed. Disconnect and try again.";
  return {};
}

struct CompletedCheck {
  std::string error;
  Clock::time_point completed;
  int64_t completedAt;
};

class ConnectionMonitor {
 public:
  void Reset() {
    ++generation_;
    processId_ = 0;
    state_ = "pending";
    detail_.clear();
    connectedAt_ = 0;
    nextCheck_ = Clock::time_point{};
  }

  nlohmann::json Snapshot(bool running, unsigned long processId) {
    const auto now = Clock::now();
    if (!running || processId_ != processId) {
      Reset();
      processId_ = processId;
    }
    if (worker_.valid() && worker_.wait_for(0s) == std::future_status::ready) {
      auto check = worker_.get();
      if (running && workerGeneration_ == generation_) {
        if (check.completed - started_ >= checkTimeout) check.error = "The connection timed out. Disconnect and try again.";
        state_ = check.error.empty() ? "passed" : "failed";
        detail_ = check.error;
        checked_ = check.completed;
        connectedAt_ = check.error.empty() ? check.completedAt : 0;
        nextCheck_ = now + checkInterval;
      }
    }
    if (!running) return Result();
    if (!RoutesUseTunnel()) {
      ++generation_; // Discard any check that started on a previous route.
      state_ = "failed";
      connectedAt_ = 0;
      detail_ = "Internet traffic is not using the VPN. Disconnect and try again.";
      nextCheck_ = now;
      return Result();
    }
    if (worker_.valid() && workerGeneration_ == generation_ && now - started_ >= checkTimeout) {
      state_ = "failed";
      connectedAt_ = 0;
      detail_ = "The connection timed out. Disconnect and try again.";
    }
    if (state_ == "passed" && now - checked_ >= evidenceLifetime) {
      state_ = "pending";
      connectedAt_ = 0;
    }
    if (!worker_.valid() && now >= nextCheck_) {
      started_ = now;
      workerGeneration_ = generation_;
      worker_ = std::async(std::launch::async, [] {
        std::string error;
        try { error = CheckConnection(); }
        catch (...) { error = "The connection check failed. Disconnect and try again."; }
        return CompletedCheck{error, Clock::now(), std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch()).count()};
      });
    }
    return Result();
  }

 private:
  nlohmann::json Result() const {
    return {{"connectionCheck", state_}, {"connectedAt", connectedAt_}, {"connectionDetail", detail_}};
  }
  std::future<CompletedCheck> worker_;
  unsigned long processId_ = 0;
  unsigned long long generation_ = 0, workerGeneration_ = 0;
  Clock::time_point started_{}, checked_{}, nextCheck_{};
  std::string state_ = "pending", detail_;
  int64_t connectedAt_ = 0;
};

ConnectionMonitor monitor;
}

nlohmann::json ManagedConnectionSnapshot(bool running, unsigned long processId) {
  return monitor.Snapshot(running, processId);
}

void ResetManagedConnectionCheck() { monitor.Reset(); }
