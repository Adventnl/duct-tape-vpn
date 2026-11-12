#include "../include/duct_native/duct_native_plugin_c_api.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wincred.h>
#include <nlohmann/json.hpp>
#include <memory>
#include <thread>
#include <bit>
#include <future>
#include <optional>
#include <chrono>
#include "managed_tunnel.h"
using Json=nlohmann::json;
namespace {
std::string Core(const Json& input){
  wchar_t path[MAX_PATH];GetModuleFileNameW(nullptr,path,MAX_PATH);
  auto dll=std::wstring(path);dll=dll.substr(0,dll.find_last_of(L"\\")+1)+L"duct_bridge.dll";
  HMODULE module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
  if(!module)throw std::runtime_error("crypto module missing");
  auto call=std::bit_cast<char*(*)(const char*)>(GetProcAddress(module,"duct_call"));
  auto release=std::bit_cast<void(*)(char*)>(GetProcAddress(module,"duct_free"));
  if(!call||!release){FreeLibrary(module);throw std::runtime_error("invalid crypto module");}
  char* out=call(input.dump().c_str());if(!out){FreeLibrary(module);throw std::runtime_error("crypto failure");}
  std::string text(out);release(out);FreeLibrary(module);
  auto value=Json::parse(text);if(!value.contains("ok"))throw std::runtime_error("crypto rejected");return value["ok"].dump();
}
Json Read(const wchar_t* name){PCREDENTIALW cred=nullptr;if(!CredReadW(name,CRED_TYPE_GENERIC,0,&cred))return Json();
  auto value=Json::parse(cred->CredentialBlob,cred->CredentialBlob+cred->CredentialBlobSize);CredFree(cred);return value;
}
void Save(const wchar_t* name,const Json& value){auto data=value.dump();if(data.size()>CRED_MAX_CREDENTIAL_BLOB_SIZE)throw std::runtime_error("credential too large");
 CREDENTIALW cred{};cred.Type=CRED_TYPE_GENERIC;cred.TargetName=const_cast<LPWSTR>(name);cred.Persist=CRED_PERSIST_LOCAL_MACHINE;cred.CredentialBlobSize=static_cast<DWORD>(data.size());cred.CredentialBlob=reinterpret_cast<LPBYTE>(data.data());if(!CredWriteW(&cred,0))throw std::runtime_error("credential storage failed");SecureZeroMemory(data.data(),data.size());}
Json Keys(){auto keys=Read(L"DuctTapeVPN/keys");if(keys.is_null()){keys=Json::parse(Core({{"op","keys"}}));Save(L"DuctTapeVPN/keys",keys);}return keys;}
std::string Pipe(const std::string& cmd){
 if(cmd!="ON"&&cmd!="OFF"&&cmd!="STATUS")throw std::runtime_error("invalid service command");
 HANDLE pipe=CreateFileW(L"\\\\.\\pipe\\DuctTapeVPN",GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,0,nullptr);
 if(pipe==INVALID_HANDLE_VALUE)throw std::runtime_error("service unavailable");
 DWORD written=0,read=0;char response[1024]{};
 bool ok=WriteFile(pipe,cmd.data(),static_cast<DWORD>(cmd.size()),&written,nullptr)&&ReadFile(pipe,response,sizeof(response)-1,&read,nullptr);CloseHandle(pipe);
 if(!ok){throw std::runtime_error("service unavailable");}
 return std::string(response,read);
}
class Plugin:public flutter::Plugin {
 public:
 explicit Plugin(flutter::PluginRegistrarWindows* registrar):registrar_(registrar){
 if(registrar->GetView())window_=GetAncestor(registrar->GetView()->GetNativeWindow(),GA_ROOT);
 delegate_=registrar->RegisterTopLevelWindowProcDelegate([this](HWND,UINT message,WPARAM w,LPARAM)->std::optional<LRESULT>{
  if(message!=WM_TIMER||w!=reinterpret_cast<UINT_PTR>(this)||!pending_)return std::nullopt;
  if(future_.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return 0;
  KillTimer(window_,reinterpret_cast<UINT_PTR>(this));
  try{auto value=future_.get();flutter::EncodableMap m;for(auto it=value.begin();it!=value.end();++it){m[flutter::EncodableValue(it.key())]=flutter::EncodableValue(it.value().get<std::string>());}pending_->Success(flutter::EncodableValue(m));}catch(...){pending_->Error("native_operation_failed","Check invitation, permission and server access");}pending_.reset();return 0;
 });
 channel=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(registrar->messenger(),"dev.ducttape/vpn",&flutter::StandardMethodCodec::GetInstance());
 channel->SetMethodCallHandler([this](const auto& call,auto result){Handle(call,std::move(result));});}
 ~Plugin() override {if(window_)KillTimer(window_,reinterpret_cast<UINT_PTR>(this));if(future_.valid())future_.wait();registrar_->UnregisterTopLevelWindowProcDelegate(delegate_);}
 private:
 flutter::PluginRegistrarWindows* registrar_;
 HWND window_{};int delegate_{};
 std::future<Json> future_;
 std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
 std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
 void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
 try {
 auto method=call.method_name();auto session=Read(L"DuctTapeVPN/session");
 auto arg=[&](const char* key)->std::string{const auto* m=std::get_if<flutter::EncodableMap>(call.arguments());if(!m)throw std::runtime_error("arguments required");return std::get<std::string>(m->at(flutter::EncodableValue(key)));};
 if(method=="snapshot"){
  if(auto managed=ManagedTunnelSnapshot()){
   flutter::EncodableMap m;
   for(auto key:{"desired","tunnel","protection","connectionCheck","connectionDetail"})m[flutter::EncodableValue(key)]=flutter::EncodableValue((*managed)[key].get<std::string>());
   m[flutter::EncodableValue("connectedAt")]=flutter::EncodableValue((*managed)["connectedAt"].get<int64_t>());
   for(auto key:{"paired","nativeAvailable"})m[flutter::EncodableValue(key)]=flutter::EncodableValue(true);
   m[flutter::EncodableValue("permission")]=flutter::EncodableValue("granted");
   m[flutter::EncodableValue("detail")]=flutter::EncodableValue("Connection checks test the VPN route, home server, DNS and IPv4 HTTPS every 10 seconds. IPv6 internet access and a kill switch are not verified.");
   result->Success(flutter::EncodableValue(m));return;
  }
  bool serviceAvailable=true;
  Json status;try{status=Json::parse(Pipe("STATUS"));}catch(...){serviceAvailable=false;auto intent=Read(L"DuctTapeVPN/intent");status={{"desired",intent.is_null()?"off":intent.value("desired","off")},{"tunnel","failed"},{"protection","unknown"}};}
  flutter::EncodableMap m;for(auto key:{"desired","tunnel","protection"})m[flutter::EncodableValue(key)]=flutter::EncodableValue(status.value(key,"unknown"));
  m[flutter::EncodableValue("nativeAvailable")]=flutter::EncodableValue(serviceAvailable);
  m[flutter::EncodableValue("paired")]=flutter::EncodableValue(!Read(L"DuctTapeVPN/config").is_null());
  m[flutter::EncodableValue("fingerprint")]=flutter::EncodableValue(session.is_null()?std::string():session.value("fingerprint",std::string()));m[flutter::EncodableValue("enrollment")]=flutter::EncodableValue(session.is_null()?"none":"pending");m[flutter::EncodableValue("owner")]=flutter::EncodableValue(false);
  m[flutter::EncodableValue("permission")]=flutter::EncodableValue("unknown");m[flutter::EncodableValue("detail")]=flutter::EncodableValue("Service and filter state require Windows traffic certification. Configuration import requires the signed installer broker.");result->Success(flutter::EncodableValue(m));
 }else if(method=="setDesired"){
  const auto& m=std::get<flutter::EncodableMap>(*call.arguments());bool on=std::get<bool>(m.at(flutter::EncodableValue("on")));
  if(ManagedTunnelSetDesired(on)){result->Success();return;}
  Save(L"DuctTapeVPN/intent",{{"desired",on?"on":"off"}});auto r=Pipe(on?"ON":"OFF");if(r!="OK")throw std::runtime_error("service rejected request");result->Success();
 }else if(method=="pair"||method=="refreshEnrollment"){
  if(pending_||!window_){result->Error("busy","Another native request is running");return;}
  Json input;
  if(method=="pair"){
   if(!session.is_null())throw std::runtime_error("already paired");
   input={{"op","begin_enrollment"},{"keys",Keys()},{"platform","windows"},{"name",arg("name")},{"invitation",arg("invitation")}};
  }else input={{"op","poll"},{"keys",Keys()},{"session",session}};
  pending_=std::move(result);
  future_=std::async(std::launch::async,[input=std::move(input),method]()->Json{
   if(method=="refreshEnrollment"){auto checkpoint=Read(L"DuctTapeVPN/enrollment-checkpoint");if(!checkpoint.is_null()){try{Core({{"op","finish_enrollment"},{"checkpoint",checkpoint}});}catch(...){}}}
   auto r=Json::parse(Core(input));
   if(method=="pair"){Save(L"DuctTapeVPN/session",r["session"]);Save(L"DuctTapeVPN/enrollment-checkpoint",r);Core({{"op","finish_enrollment"},{"checkpoint",r}});return {{"status","pending"},{"fingerprint",r["fingerprint"]}};}
   CredDeleteW(L"DuctTapeVPN/enrollment-checkpoint",CRED_TYPE_GENERIC,0);
   if(r.contains("config"))Save(L"DuctTapeVPN/config",r["config"]);
   return {{"status",r["status"]}};
  });
  SetTimer(window_,reinterpret_cast<UINT_PTR>(this),50,nullptr);
 }else{result->NotImplemented();}
 }catch(...){result->Error("native_operation_failed","Check enrollment and the installed Windows service");}
 }
};
}
void DuctNativePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar){auto* r=flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);r->AddPlugin(std::make_unique<Plugin>(r));}
