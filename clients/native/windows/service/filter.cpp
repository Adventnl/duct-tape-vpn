#include "filter.h"
#include <initguid.h>
#include <fwpmu.h>
#include "wfp_compat.h"
#include <stdexcept>
#include <vector>
static const GUID provider={0x695dd8e1,0x2578,0x463a,{0x8c,0x16,0x4b,0x5c,0xa4,0x1b,0xd3,0x80}};
static const GUID sublayer={0x338c3724,0xb579,0x4c30,{0xb1,0x33,0xbc,0x64,0xb4,0x3a,0x5d,0xa2}};
struct Engine{HANDLE h{};Engine(){if(FwpmEngineOpen0(nullptr,RPC_C_AUTHN_WINNT,nullptr,nullptr,&h))throw std::runtime_error("WFP engine unavailable");}~Engine(){if(h)FwpmEngineClose0(h);}};
static void Check(DWORD code){if(code!=ERROR_SUCCESS)throw std::runtime_error("WFP operation failed");}
static void Clear(HANDLE h){
 FWPM_FILTER_ENUM_TEMPLATE0 t{};t.providerKey=const_cast<GUID*>(&provider);HANDLE e{};Check(FwpmFilterCreateEnumHandle0(h,&t,&e));
 FWPM_FILTER0** filters=nullptr;UINT32 count=0;DWORD result;
 do{result=FwpmFilterEnum0(h,e,128,&filters,&count);if(result)break;for(UINT32 i=0;i<count;i++)Check(FwpmFilterDeleteById0(h,filters[i]->filterId));FwpmFreeMemory0(reinterpret_cast<void**>(&filters));}while(count);
 FwpmFilterDestroyEnumHandle0(h,e);Check(result);
}
static void Add(HANDLE h,const GUID& layer,FWP_ACTION_TYPE action,UINT8 weight,std::vector<FWPM_FILTER_CONDITION0> conditions={}){
 FWPM_FILTER0 filter{};filter.displayData.name=const_cast<wchar_t*>(L"Duct-Tape VPN protection");filter.providerKey=const_cast<GUID*>(&provider);filter.layerKey=layer;filter.subLayerKey=sublayer;
 filter.flags=FWPM_FILTER_FLAG_PERSISTENT;filter.action.type=action;filter.weight.type=FWP_UINT8;filter.weight.uint8=weight;filter.numFilterConditions=static_cast<UINT32>(conditions.size());filter.filterCondition=conditions.data();Check(FwpmFilterAdd0(h,&filter,nullptr,nullptr));
}
void BlockOutsideTunnel(const wchar_t* tunnelExe,UINT32 remoteV4,UINT16 port,UINT64 tunnelLuid){
 Engine e;Check(FwpmTransactionBegin0(e.h,0));
 try{
  FWPM_PROVIDER0 p{};p.providerKey=provider;p.displayData.name=const_cast<wchar_t*>(L"Duct-Tape VPN");p.flags=FWPM_PROVIDER_FLAG_PERSISTENT;
  DWORD code=FwpmProviderAdd0(e.h,&p,nullptr);if(code!=static_cast<DWORD>(FWP_E_ALREADY_EXISTS))Check(code);
  FWPM_SUBLAYER0 s{};s.subLayerKey=sublayer;s.providerKey=const_cast<GUID*>(&provider);s.displayData.name=p.displayData.name;s.weight=0x7000;s.flags=FWPM_SUBLAYER_FLAG_PERSISTENT;
  code=FwpmSubLayerAdd0(e.h,&s,nullptr);if(code!=static_cast<DWORD>(FWP_E_ALREADY_EXISTS))Check(code);Clear(e.h);
  for(auto layer:{FWPM_LAYER_ALE_AUTH_CONNECT_V4,FWPM_LAYER_ALE_AUTH_CONNECT_V6}){
   FWPM_FILTER_CONDITION0 loop{};loop.fieldKey=FWPM_CONDITION_FLAGS;loop.matchType=FWP_MATCH_FLAGS_ALL_SET;loop.conditionValue.type=FWP_UINT32;loop.conditionValue.uint32=FWP_CONDITION_FLAG_IS_LOOPBACK;
   Add(e.h,layer,FWP_ACTION_PERMIT,15,{loop});
   if(tunnelLuid){FWPM_FILTER_CONDITION0 tun{};tun.fieldKey=FWPM_CONDITION_IP_LOCAL_INTERFACE;tun.matchType=FWP_MATCH_EQUAL;tun.conditionValue.type=FWP_UINT64;tun.conditionValue.uint64=&tunnelLuid;Add(e.h,layer,FWP_ACTION_PERMIT,14,{tun});}
   Add(e.h,layer,FWP_ACTION_BLOCK,1);
  }
  if(remoteV4 && port){
  FWP_BYTE_BLOB* app=nullptr;Check(FwpmGetAppIdFromFileName0(tunnelExe,&app));
  FWPM_FILTER_CONDITION0 exe{},ip{},udp{},dst{};
  exe.fieldKey=FWPM_CONDITION_ALE_APP_ID;exe.matchType=FWP_MATCH_EQUAL;exe.conditionValue.type=FWP_BYTE_BLOB_TYPE;exe.conditionValue.byteBlob=app;
  ip.fieldKey=FWPM_CONDITION_IP_REMOTE_ADDRESS;ip.matchType=FWP_MATCH_EQUAL;ip.conditionValue.type=FWP_UINT32;ip.conditionValue.uint32=remoteV4;
  udp.fieldKey=FWPM_CONDITION_IP_PROTOCOL;udp.matchType=FWP_MATCH_EQUAL;udp.conditionValue.type=FWP_UINT8;udp.conditionValue.uint8=IPPROTO_UDP;
  dst.fieldKey=FWPM_CONDITION_IP_REMOTE_PORT;dst.matchType=FWP_MATCH_EQUAL;dst.conditionValue.type=FWP_UINT16;dst.conditionValue.uint16=port;
  Add(e.h,FWPM_LAYER_ALE_AUTH_CONNECT_V4,FWP_ACTION_PERMIT,15,{exe,ip,udp,dst});FwpmFreeMemory0(reinterpret_cast<void**>(&app));
  }
  Check(FwpmTransactionCommit0(e.h));
 }catch(...){FwpmTransactionAbort0(e.h);throw;}
}
void RemoveOwnedFilters(){Engine e;Check(FwpmTransactionBegin0(e.h,0));try{Clear(e.h);DWORD c=FwpmSubLayerDeleteByKey0(e.h,&sublayer);if(c!=static_cast<DWORD>(FWP_E_SUBLAYER_NOT_FOUND))Check(c);c=FwpmProviderDeleteByKey0(e.h,&provider);if(c!=static_cast<DWORD>(FWP_E_PROVIDER_NOT_FOUND))Check(c);Check(FwpmTransactionCommit0(e.h));}catch(...){FwpmTransactionAbort0(e.h);throw;}}
