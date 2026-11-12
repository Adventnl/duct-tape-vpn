import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/vpn_controller.dart';
import 'components.dart';

class Settings extends StatefulWidget {
  const Settings({super.key, required this.controller});
  final VpnController controller;
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final link = TextEditingController(),
      name = TextEditingController(),
      endpoint = TextEditingController(),
      releaseHash = TextEditingController(),
      releaseVersion = TextEditingController();
  String? message, fingerprint, invitation, ownerPublic;
  bool working = false;
  List<Map<Object?, Object?>> devices = [];

  Future<void> perform(Future<void> Function() task) async {
    if (working) return;
    setState(() {
      working = true;
      message = null;
    });
    try {
      await task();
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not complete the request. Check the invitation, server access and native service, then try again.',
        );
      }
    } finally {
      await widget.controller.refresh();
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> admin(Map<String, Object?> operation) async {
    final result = await widget.controller.port.administer(operation);
    if (!mounted) return;
    setState(() {
      if (result['devices'] is List) {
        devices = (result['devices'] as List)
            .map((x) => Map<Object?, Object?>.from(x as Map))
            .toList();
      }
      if (result['invitation'] is String) {
        invitation = result['invitation'] as String;
      }
      message = 'Request completed.';
    });
  }

  Widget action(
    String text,
    Future<void> Function() task, {
    bool destructive = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: destructive
            ? TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              )
            : null,
        onPressed: working ? null : () => perform(task),
        child: Text(text),
      ),
    ),
  );

  Future<void> rename(Map<Object?, Object?> device) async {
    final edit = TextEditingController(text: device['name'] as String? ?? '');
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename device'),
        content: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: CupertinoTextField(
            controller: edit,
            maxLength: 80,
            autofocus: true,
            placeholder: 'Device name',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, edit.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // The dialog route may still be animating when its future resolves.
    if (value != null && value.isNotEmpty && mounted) {
      await perform(
        () => admin({'type': 'rename', 'id': device['id'], 'name': value}),
      );
    }
    Future<void>.delayed(const Duration(seconds: 1), edit.dispose);
  }

  @override
  void dispose() {
    link.dispose();
    name.dispose();
    endpoint.dispose();
    releaseHash.dispose();
    releaseVersion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      final displayedFingerprint = fingerprint ?? state.fingerprint;
      return Scaffold(
        backgroundColor: AppColors.canvas(context),
        appBar: AppBar(
          title: const Text(
            'Settings',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(CupertinoIcons.chevron_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: Text(
                      'Your connection.',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  if (working)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          message!,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  if (!state.nativeAvailable)
                    SettingsGroup(
                      title: 'Connection setup',
                      footer: 'A native VPN service is required. The interface cannot create a tunnel by itself.',
                      children: [
                        const SettingsRow(
                          title: 'Native service unavailable',
                          subtitle: 'Install or start the VPN service on this device.',
                          icon: CupertinoIcons.exclamationmark_circle,
                        ),
                        action('Check again', widget.controller.refresh),
                      ],
                    ),
                  if (!state.paired &&
                      defaultTargetPlatform == TargetPlatform.macOS)
                    SettingsGroup(
                      title: 'Owner MacBook',
                      footer: 'Transfer only the public keys to your trusted server console. Import the signed bundle returned over that same trusted connection.',
                      children: [
                        action('Set up Owner MacBook', () async {
                          final keys = await widget.controller.port
                              .ownerPublic();
                          if (mounted) {
                            setState(
                              () => ownerPublic = const JsonEncoder.withIndent(
                                '  ',
                              ).convert(keys),
                            );
                          }
                        }),
                        if (ownerPublic != null) ...[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(
                              ownerPublic!,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          GroupField(
                            controller: link,
                            label: 'Trusted Owner bundle',
                            maxLines: 5,
                            maxLength: 16384,
                          ),
                          action('Import trusted bundle', () async {
                            await widget.controller.port.importOwner(link.text);
                            link.clear();
                            if (mounted) {
                              setState(
                                () => message = 'Owner configuration imported.',
                              );
                            }
                          }),
                        ],
                      ],
                    ),
                  if (!state.paired &&
                      ownerPublic == null &&
                      state.enrollment != 'pending')
                    SettingsGroup(
                      title: 'Pair with home',
                      footer: 'Paste the invitation from your Owner MacBook. Your private keys stay on this device.',
                      children: [
                        GroupField(
                          controller: name,
                          label: 'Device name',
                          maxLength: 80,
                        ),
                        GroupField(
                          controller: link,
                          label: 'Invitation link',
                          maxLines: 3,
                          maxLength: 4096,
                        ),
                        action('Request pairing', () async {
                          if (link.text.trim().isEmpty ||
                              name.text.trim().isEmpty) {
                            setState(
                              () => message =
                                  'Enter a device name and invitation link.',
                            );
                            return;
                          }
                          final result = await widget.controller.port.pair(
                            link.text.trim(),
                            name.text.trim(),
                          );
                          link.clear();
                          if (mounted) {
                            setState(() {
                              fingerprint = result['fingerprint'] as String?;
                              message = 'Waiting for Owner approval. Compare the fingerprint on both devices.';
                            });
                          }
                        }),
                      ],
                    ),
                  if (!state.paired &&
                      displayedFingerprint != null &&
                      displayedFingerprint.isNotEmpty)
                    SettingsGroup(
                      title: 'Device approval',
                      footer: 'Approve only when this fingerprint matches the one on your Owner device.',
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(displayedFingerprint),
                        ),
                        action('Check approval', () async {
                          final result = await widget.controller.port
                              .refreshEnrollment();
                          if (mounted) {
                            setState(
                              () => message = 'Enrollment: ${result['status']}',
                            );
                          }
                        }),
                      ],
                    ),
                  if (state.owner) ...[
                    SettingsGroup(
                      title: 'Your devices',
                      children: [
                        action(
                          'Invite a device',
                          () => admin({'type': 'invite', 'ttl_seconds': 300}),
                        ),
                        if (invitation != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                QrImageView(
                                  data: invitation!,
                                  size: 220,
                                  backgroundColor: Colors.white,
                                ),
                                SelectableText(invitation!),
                                const SizedBox(height: 8),
                                const Text(
                                  'Expires in five minutes. Share privately.',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        action('Review devices', () => admin({'type': 'list'})),
                        for (final device in devices)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SettingsRow(
                                title: '${device['name']}',
                                subtitle: '${device['status']}',
                                icon: CupertinoIcons.device_phone_portrait,
                              ),
                              action('Rename', () => rename(device)),
                              if (device['status'] == 'pending') ...[
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: SelectableText(
                                    '${device['fingerprint']}',
                                  ),
                                ),
                                action(
                                  'Fingerprint matches, approve',
                                  () => admin({
                                    'type': 'approve',
                                    'id': device['id'],
                                    'fingerprint': device['fingerprint'],
                                  }),
                                ),
                                action(
                                  'Reject',
                                  () => admin({
                                    'type': 'reject',
                                    'id': device['id'],
                                  }),
                                  destructive: true,
                                ),
                              ],
                              if (device['role'] != 'owner' &&
                                  device['status'] == 'active')
                                action(
                                  'Revoke access',
                                  () => admin({
                                    'type': 'revoke',
                                    'id': device['id'],
                                  }),
                                  destructive: true,
                                ),
                            ],
                          ),
                      ],
                    ),
                    SettingsGroup(
                      title: 'Server endpoint',
                      children: [
                        GroupField(
                          controller: endpoint,
                          label: 'Public WireGuard endpoint',
                        ),
                        action(
                          'Approve endpoint change',
                          () => admin({
                            'type': 'endpoint',
                            'endpoint': endpoint.text.trim(),
                          }),
                        ),
                      ],
                    ),
                    SettingsGroup(
                      title: 'Client releases',
                      footer: 'Release approval does not install an update or approve a server deployment.',
                      children: [
                        GroupField(
                          controller: releaseVersion,
                          label: 'Release version',
                          numeric: true,
                        ),
                        GroupField(
                          controller: releaseHash,
                          label: 'Verified artifact SHA-256',
                          maxLength: 64,
                        ),
                        action('Approve client release', () async {
                          final version = int.tryParse(releaseVersion.text);
                          if (version == null ||
                              !RegExp(r'^[a-fA-F0-9]{64}$')
                                  .hasMatch(releaseHash.text.trim())) {
                            setState(
                              () => message = 'Enter a numeric version and the full 64-character SHA-256.',
                            );
                            return;
                          }
                          await admin({
                            'type': 'approve_release',
                            'version': version,
                            'sha256': releaseHash.text.trim(),
                          });
                        }),
                      ],
                    ),
                  ],
                  SettingsGroup(
                    title: 'Connection details',
                    children: [
                      SettingsRow(
                        title: 'Status',
                        subtitle: state.label(DateTime.now()),
                      ),
                      SettingsRow(
                        title: 'Connection',
                        subtitle: state.connectionMessage(DateTime.now()),
                      ),
                      if (state.detail != null && state.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            state.detail!,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
