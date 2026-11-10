#pragma once
#include <flutter_plugin_registrar.h>
#ifdef DUCT_NATIVE_PLUGIN_IMPL
#define DUCT_EXPORT __declspec(dllexport)
#else
#define DUCT_EXPORT __declspec(dllimport)
#endif
extern "C" DUCT_EXPORT void DuctNativePluginCApiRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);
