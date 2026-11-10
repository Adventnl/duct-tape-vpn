#include "filter.h"
#include <sddl.h>
#include <string>
#include <stdexcept>
#include <thread>
#include <atomic>
#include <mutex>
#include <bit>
// Exact installed path and preconfigured service only. The UI cannot supply an executable/config path.
static SERVICE_STATUS_HANDLE statusHandle;
static SERVICE_STATUS status={SERVICE_WIN32_OWN_PROCESS,SERVICE_START_PENDING,SERVICE_ACCEPT_STOP,NO_ERROR,0,0,0};
static HANDLE stopEvent;
static constexpr wchar_t tunnelService[]=L"WireGuardTunnel$dtvpn";
static bool Desired(){DWORD value=0,size=sizeof(value);RegGetValueW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\DuctTapeVPN",L"DesiredOn",RRF_RT_REG_DWORD,nullptr,&value,&size);return value==1;}
static void Save(bool on){HKEY key;DWORD value=on?1:0;if(RegCreateKeyExW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\DuctTapeVPN",0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr))throw std::runtime_error("state unavailable");auto e=RegSetValueExW(key,L"DesiredOn",0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value));RegCloseKey(key);if(e)throw std::runtime_error("state write failed");}
static bool Tunnel(bool start){SC_HANDLE scm=OpenSCManagerW(nullptr,nullptr,SC_MANAGER_CONNECT);if(!scm)throw std::runtime_error("SCM unavailable");SC_HANDLE svc=OpenServiceW(scm,tunnelService,SERVICE_START|SERVICE_STOP|SERVICE_QUERY_STATUS);CloseServiceHandle(scm);if(!svc)throw std::runtime_error("tunnel service missing");SERVICE_STATUS state{};bool ok;if(start)ok=StartServiceW(svc,0,nullptr)||GetLastError()==ERROR_SERVICE_ALREADY_RUNNING;else ok=ControlService(svc,SERVICE_CONTROL_STOP,&state)||GetLastError()==ERROR_SERVICE_NOT_ACTIVE;CloseServiceHandle(svc);return ok;}
static std::mutex controlMutex;
static std::atomic<bool> tunnelUp{false},filtersEnforced{false};
static void Binding(UINT32& address,UINT16& port){
 DWORD rawPort=0,size=sizeof(address);if(RegGetValueW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\DuctTapeVPN",L"RemoteIPv4",RRF_RT_REG_DWORD,nullptr,&address,&size))throw std::runtime_error("endpoint binding missing");
 size=sizeof(rawPort);if(RegGetValueW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\DuctTapeVPN",L"RemotePort",RRF_RT_REG_DWORD,nullptr,&rawPort,&size)||rawPort<1||rawPort>65535)throw std::runtime_error("endpoint port missing");port=static_cast<UINT16>(rawPort);
}
static UINT64 AdapterLuid(){
 wchar_t path[MAX_PATH];GetModuleFileNameW(nullptr,path,MAX_PATH);std::wstring dll(path);dll=dll.substr(0,dll.find_last_of(L"\\")+1)+L"wireguard.dll";
 HMODULE module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);if(!module)return 0;
 auto open=std::bit_cast<void*(*)(LPCWSTR)>(GetProcAddress(module,"WireGuardOpenAdapter"));auto luid=std::bit_cast<void(*)(void*,UINT64*)>(GetProcAddress(module,"WireGuardGetAdapterLUID"));auto close=std::bit_cast<void(*)(void*)>(GetProcAddress(module,"WireGuardCloseAdapter"));UINT64 result=0;
 if(open&&luid&&close){auto adapter=open(L"dtvpn");if(adapter){luid(adapter,&result);close(adapter);}}FreeLibrary(module);return result;
}
static void Maintain(){
 std::lock_guard<std::mutex> guard(controlMutex);if(!Desired())return;
 wchar_t exe[MAX_PATH];GetModuleFileNameW(nullptr,exe,MAX_PATH);UINT32 remote=0;UINT16 port=0;
 try{Binding(remote,port);}catch(...){BlockOutsideTunnel(exe,0,0,0);filtersEnforced=true;throw;}
 auto luid=AdapterLuid();BlockOutsideTunnel(exe,remote,port,luid);filtersEnforced=true;
 if(!Tunnel(true))throw std::runtime_error("tunnel start failed");
 if(!luid){for(int i=0;i<20&&Desired();i++){Sleep(100);luid=AdapterLuid();if(luid)break;}}
 if(luid){BlockOutsideTunnel(exe,remote,port,luid);tunnelUp=true;}else{tunnelUp=false;throw std::runtime_error("adapter unavailable");}
}
static void WINAPI Control(DWORD control){if(control==SERVICE_CONTROL_STOP){status.dwCurrentState=SERVICE_STOP_PENDING;SetServiceStatus(statusHandle,&status);SetEvent(stopEvent);}}
static void WINAPI Main(DWORD,wchar_t**){
 statusHandle=RegisterServiceCtrlHandlerW(L"DuctTapeAgent",Control);if(!statusHandle)return;stopEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);status.dwCurrentState=SERVICE_RUNNING;SetServiceStatus(statusHandle,&status);
 std::thread watchdog([]{unsigned attempt=0;while(WaitForSingleObject(stopEvent,0)==WAIT_TIMEOUT){if(Desired()){try{Maintain();attempt=0;}catch(...){tunnelUp=false;attempt=(attempt<6?attempt+1:6);}}WaitForSingleObject(stopEvent,(1u<<attempt)*1000);}});
 // Installer must set this DACL to the single authorized local user SID plus SYSTEM/Admins.
 // Fail closed until a reviewed DACL and endpoint/interface binding exist; never expose an Everyone pipe.
 wchar_t sddl[1024]{};DWORD size=sizeof(sddl);
 if(RegGetValueW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\DuctTapeVPN",L"PipeSDDL",RRF_RT_REG_SZ,nullptr,sddl,&size)!=ERROR_SUCCESS){SetEvent(stopEvent);}
 PSECURITY_DESCRIPTOR sd=nullptr;
 if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,SDDL_REVISION_1,&sd,nullptr))SetEvent(stopEvent);
 SECURITY_ATTRIBUTES security{sizeof(security),sd,FALSE};
 while(WaitForSingleObject(stopEvent,0)==WAIT_TIMEOUT){
  HANDLE pipe=CreateNamedPipeW(L"\\\\.\\pipe\\DuctTapeVPN",PIPE_ACCESS_DUPLEX|FILE_FLAG_FIRST_PIPE_INSTANCE,PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_NOWAIT|PIPE_REJECT_REMOTE_CLIENTS,1,1024,32,5000,&security);
  if(pipe==INVALID_HANDLE_VALUE)break;
  BOOL connected=FALSE;while(WaitForSingleObject(stopEvent,100)==WAIT_TIMEOUT){connected=ConnectNamedPipe(pipe,nullptr);if(connected||GetLastError()==ERROR_PIPE_CONNECTED){connected=TRUE;break;}if(GetLastError()!=ERROR_PIPE_LISTENING)break;}
  if(connected){char command[32]{};DWORD read=0,written=0;std::string reply="ERROR";
   BOOL received=FALSE;for(int i=0;i<100;i++){received=ReadFile(pipe,command,31,&read,nullptr);if(received)break;if(GetLastError()!=ERROR_NO_DATA)break;Sleep(10);}
   if(received){
    std::string cmd(command,read);
    try{
     if(cmd=="STATUS")reply=std::string("{\"desired\":\"")+(Desired()?"on":"off")+"\",\"tunnel\":\""+(tunnelUp?"up":"reconnecting")+"\",\"protection\":\""+(filtersEnforced?(tunnelUp?"enforced":"blocked"):"unknown")+"\"}";
     else if(cmd=="OFF"){std::lock_guard<std::mutex> guard(controlMutex);Save(false);if(!Tunnel(false))throw std::runtime_error("stop failed");RemoveOwnedFilters();filtersEnforced=false;tunnelUp=false;reply="OK";}
     else if(cmd=="ON"){
      Save(true);Maintain();reply="OK";
     }
    }catch(...){reply="ERROR";}
   }
   WriteFile(pipe,reply.data(),static_cast<DWORD>(reply.size()),&written,nullptr);
  }
  DisconnectNamedPipe(pipe);CloseHandle(pipe);
 }
 SetEvent(stopEvent);watchdog.join();if(sd)LocalFree(sd);CloseHandle(stopEvent);status.dwCurrentState=SERVICE_STOPPED;SetServiceStatus(statusHandle,&status);
 // Persistent filters are never removed during shutdown, crash or UI close.
}
int wmain(int argc,wchar_t** argv){
 if(argc==3 && wcscmp(argv[1],L"/tunnel")==0){
  // Signed, installed directory is ACL-restricted; never search CWD or PATH for privileged DLLs.
  wchar_t path[MAX_PATH];GetModuleFileNameW(nullptr,path,MAX_PATH);std::wstring dll(path);dll=dll.substr(0,dll.find_last_of(L"\\")+1)+L"tunnel.dll";
  HMODULE module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);if(!module)return 1;
  auto start=std::bit_cast<BOOL(__cdecl*)(LPCWSTR)>(GetProcAddress(module,"WireGuardTunnelService"));return start&&start(argv[2])?0:1;
 }
 SERVICE_TABLE_ENTRYW table[]={{const_cast<LPWSTR>(L"DuctTapeAgent"),Main},{nullptr,nullptr}};return StartServiceCtrlDispatcherW(table)?0:1;
}
