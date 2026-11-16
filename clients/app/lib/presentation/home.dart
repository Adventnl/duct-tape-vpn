import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../application/vpn_controller.dart';
import '../domain/vpn_state.dart';
import 'components.dart';
import 'settings.dart';

class Home extends StatelessWidget {
  const Home({super.key, required this.controller});
  final VpnController controller;
  void _settings(BuildContext context) => Navigator.of(context).push(
    CupertinoPageRoute<void>(builder: (_) => Settings(controller: controller)),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final on = state.desired == Desired.on;
      final available = state.paired && state.nativeAvailable;
      final now = DateTime.now();
      final connection = state.connectionAt(now);
      final active = connection == ConnectionStatus.connected;
      final connecting = connection == ConnectionStatus.connecting;
      final blue = AppColors.blue(context);
      final heading = state.label(now);
      final message = state.connectionMessage(now);
      final action = !state.nativeAvailable
          ? 'Check setup'
          : !state.paired
          ? 'Set up connection'
          : on
          ? 'Disconnect'
          : 'Connect';
      return Scaffold(
        backgroundColor: AppColors.canvas(context),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (box.maxHeight - 44).clamp(0, double.infinity),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: const Text(
                                      'VPN',
                                      style: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Duct-Tape',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: AppColors.secondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Glass(
                              radius: 24,
                              child: IconButton(
                                tooltip: 'Setup and settings',
                                onPressed: () => _settings(context),
                                icon: Icon(
                                  CupertinoIcons.gear_alt,
                                  color: AppColors.ink(context),
                                  size: 23,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 44),
                          child: Column(
                            children: [
                              Semantics(
                                label: 'VPN ${heading.toLowerCase()}',
                                excludeSemantics: true,
                                child: AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 240),
                                  width: 132,
                                  height: 132,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: active
                                        ? blue.withValues(alpha: .09)
                                        : AppColors.surface(context),
                                    border: Border.all(
                                      color: active
                                          ? blue.withValues(alpha: .22)
                                          : AppColors.secondary(context)
                                                .withValues(alpha: .12),
                                    ),
                                  ),
                                  child: connecting
                                      ? const Center(
                                          child: CupertinoActivityIndicator(
                                            radius: 20,
                                          ),
                                        )
                                      : Icon(
                                          CupertinoIcons.power,
                                          size: 49,
                                          color: active
                                              ? blue
                                              : AppColors.secondary(context),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  heading,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -.7,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              if (message.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.45,
                                    color: AppColors.secondary(context),
                                  ),
                                ),
                              ),
                              ],
                              const SizedBox(height: 28),
                              FilledButton(
                                onPressed: controller.busy
                                    ? null
                                    : available
                                    ? controller.toggle
                                    : () => _settings(context),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 3,
                                  ),
                                  child: controller.busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(action),
                                ),
                              ),
                              if (controller.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      controller.error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SettingsGroup(
                              children: [
                                SettingsRow(
                                  title: 'Server',
                                  subtitle: state.paired ? null : 'Activate this device',
                                  icon: CupertinoIcons.house,
                                  onTap: () => _settings(context),
                                ),
                              ],
                            ),
                            Glass(
                              child: SettingsRow(
                                title: 'Connection details',
                                icon: CupertinoIcons.info_circle,
                                onTap: () => _settings(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
