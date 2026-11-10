import 'package:flutter/material.dart';
import 'application/vpn_controller.dart';
import 'infrastructure/native_vpn.dart';
import 'presentation/home.dart';
void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(DuctTapeApp(controller:VpnController(NativeVpn()))); }
class DuctTapeApp extends StatefulWidget {
  const DuctTapeApp({super.key,required this.controller});
  final VpnController controller;
  @override State<DuctTapeApp> createState() => _DuctTapeAppState();
}
class _DuctTapeAppState extends State<DuctTapeApp> {
  @override void initState(){super.initState();widget.controller.start();}
  @override void dispose(){widget.controller.dispose();super.dispose();}
  ThemeData theme(Brightness brightness) {
    final dark=brightness==Brightness.dark;
    return ThemeData(useMaterial3:true,brightness:brightness,scaffoldBackgroundColor:dark?const Color(0xff151918):const Color(0xfff5f4ef),
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xff315f50),brightness:brightness),
      textTheme:const TextTheme(headlineMedium:TextStyle(fontSize:30,fontWeight:FontWeight.w400,letterSpacing:-0.8),bodyMedium:TextStyle(fontSize:15,height:1.5)),
      inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder()),
      appBarTheme:const AppBarTheme(centerTitle:false,backgroundColor:Colors.transparent,surfaceTintColor:Colors.transparent,elevation:0));
  }
  @override Widget build(BuildContext context)=>MaterialApp(title:'Duct-Tape VPN',debugShowCheckedModeBanner:false,theme:theme(Brightness.light),darkTheme:theme(Brightness.dark),home:Home(controller:widget.controller));
}
