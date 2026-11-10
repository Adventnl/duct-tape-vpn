import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import '../application/vpn_controller.dart';
class Settings extends StatefulWidget {
  const Settings({super.key,required this.controller});
  final VpnController controller;
  @override State<Settings> createState()=>_SettingsState();
}
class _SettingsState extends State<Settings> {
  final link=TextEditingController(),name=TextEditingController(),endpoint=TextEditingController(),releaseHash=TextEditingController(),releaseVersion=TextEditingController();
  String? message,fingerprint,invitation,ownerPublic;
  bool working=false;
  List<Map<Object?,Object?>> devices=[];
  Future<void> perform(Future<void> Function() task) async {setState(()=>working=true);try{await task();}catch(_){if(mounted)setState(()=>message='Request failed. Check the invitation, server access and native service.');}finally{if(mounted)setState(()=>working=false);await widget.controller.refresh();}}
  Future<void> admin(Map<String,Object?> op) async {
    final result=await widget.controller.port.administer(op);
    if(!mounted)return;
    setState((){if(result['devices'] is List){devices=(result['devices'] as List).map((x)=>Map<Object?,Object?>.from(x as Map)).toList();}invitation=result['invitation'] as String?;message='Request completed.';});
  }
  @override void dispose(){link.dispose();name.dispose();endpoint.dispose();releaseHash.dispose();releaseVersion.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    final state=widget.controller.state;
    final displayedFingerprint=fingerprint??state.fingerprint;
    return Scaffold(appBar:AppBar(title:const Text('Setup & settings')),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:ListView(padding:const EdgeInsets.all(24),children:[
      if(!state.paired && defaultTargetPlatform==TargetPlatform.macOS)...[
        OutlinedButton(onPressed:working?null:()=>perform(()async{final keys=await widget.controller.port.ownerPublic();if(mounted)setState(()=>ownerPublic=const JsonEncoder.withIndent('  ').convert(keys));}),child:const Text('Set up Owner MacBook')),
        if(ownerPublic!=null)...[const Text('Transfer these public keys to your trusted server console. Import the signed Owner bundle returned over that same trusted connection.'),SelectableText(ownerPublic!),const SizedBox(height:12),TextField(controller:link,maxLines:5,maxLength:16384,decoration:const InputDecoration(labelText:'Trusted Owner bundle')),FilledButton(onPressed:working?null:()=>perform(()async{await widget.controller.port.importOwner(link.text);link.clear();if(mounted)setState(()=>message='Owner configuration imported.');}),child:const Text('Import trusted Owner bundle'))],
        const SizedBox(height:24),
      ],
      if(!state.paired && ownerPublic==null && state.enrollment!='pending')...[
        Text('Pair with home',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:12),
        const Text('Open the invitation from your Owner MacBook, or paste its link below. Your private keys stay on this device.'),const SizedBox(height:24),
        TextField(controller:name,maxLength:80,decoration:const InputDecoration(labelText:'Device name'),textInputAction:TextInputAction.next),const SizedBox(height:16),
        TextField(controller:link,decoration:const InputDecoration(labelText:'Invitation link'),autocorrect:false,enableSuggestions:false,maxLines:3,maxLength:4096),const SizedBox(height:16),
        FilledButton(onPressed:working?null:()=>perform(()async{final result=await widget.controller.port.pair(link.text.trim(),name.text.trim());link.clear();if(mounted)setState((){fingerprint=result['fingerprint'] as String?;message='Pending Owner approval. Compare this fingerprint on both devices.';});}),child:const Text('Request pairing')),
      ],
      if(displayedFingerprint!=null && displayedFingerprint.isNotEmpty && !state.paired)...[const SizedBox(height:24),const Text('Device fingerprint'),SelectableText(displayedFingerprint),const SizedBox(height:12),OutlinedButton(onPressed:working?null:()=>perform(()async{final result=await widget.controller.port.refreshEnrollment();if(mounted)setState(()=>message='Enrollment: ${result['status']}');}),child:const Text('Check approval'))],
      if(state.owner)...[
        Text('Owner',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:16),
        OutlinedButton(onPressed:working?null:()=>perform(()=>admin({'type':'invite','ttl_seconds':300})),child:const Text('Invite a device')),
        if(invitation!=null)...[QrImageView(data:invitation!,size:220,backgroundColor:Colors.white),SelectableText(invitation!),const Text('Expires in five minutes. Share privately.')],
        OutlinedButton(onPressed:working?null:()=>perform(()=>admin({'type':'list'})),child:const Text('Review devices')),
        const SizedBox(height:24),
        TextField(controller:endpoint,decoration:const InputDecoration(labelText:'Public WireGuard endpoint',hintText:'your-host.example:port'),autocorrect:false,enableSuggestions:false),
        TextButton(onPressed:working?null:()=>perform(()=>admin({'type':'endpoint','endpoint':endpoint.text.trim()})),child:const Text('Approve endpoint change')),
        const SizedBox(height:24),
        TextField(controller:releaseVersion,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Client release version')),
        const SizedBox(height:12),
        TextField(controller:releaseHash,maxLength:64,decoration:const InputDecoration(labelText:'Verified artifact SHA-256'),autocorrect:false,enableSuggestions:false),
        TextButton(onPressed:working?null:()=>perform(()=>admin({'type':'approve_release','version':int.parse(releaseVersion.text),'sha256':releaseHash.text.trim()})),child:const Text('Approve client release')),
        const Text('Release approval does not install an update or approve a server deployment.'),
        for(final device in devices) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${device['name']} · ${device['status']}'),TextButton(onPressed:working?null:()async{var edit=device['name'] as String? ?? '';final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Rename device'),content:TextFormField(initialValue:edit,onChanged:(value)=>edit=value,maxLength:80,autofocus:true),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),TextButton(onPressed:()=>Navigator.pop(ctx,edit.trim()),child:const Text('Save'))]));if(value!=null && mounted){await perform(()=>admin({'type':'rename','id':device['id'],'name':value}));}},child:const Text('Rename')),if(device['status']=='pending')...[SelectableText('${device['fingerprint']}'),Wrap(spacing:12,children:[OutlinedButton(onPressed:working?null:()=>perform(()=>admin({'type':'approve','id':device['id'],'fingerprint':device['fingerprint']})),child:const Text('Fingerprint matches · approve')),TextButton(onPressed:working?null:()=>perform(()=>admin({'type':'reject','id':device['id']})),child:const Text('Reject'))])],if(device['role']!='owner'&&device['status']=='active')TextButton(onPressed:working?null:()=>perform(()=>admin({'type':'revoke','id':device['id']})),child:const Text('Revoke'))])),
      ],
      if(message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:20),child:Semantics(liveRegion:true,child:Text(message!))),
      const Divider(height:48),Text('Diagnostics',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:16),
      SelectableText('Requested: ${state.desired.name}\nTunnel: ${state.tunnel.name}\nProtection: ${state.protection.name}\nPermission: ${state.permission.name}\n${state.detail??''}'),
      const SizedBox(height:24),const Text('Strict routing is the default. Local trusted-network exceptions are disabled until the platform can enforce them safely.'),
    ]))));
  }
}
