#pragma once
#include <winsock2.h>
#include <windows.h>
#include <cstdint>
// Persistent, application-owned WFP filters survive service crashes. Installation is privileged.
void BlockOutsideTunnel(const wchar_t* tunnelExe,UINT32 remoteV4,UINT16 port,UINT64 tunnelLuid);
void RemoveOwnedFilters();
