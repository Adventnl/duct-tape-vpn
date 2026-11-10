import 'package:flutter/material.dart';
import '../application/vpn_controller.dart';
import '../domain/vpn_state.dart';
import 'settings.dart';

class Home extends StatelessWidget {
  const Home({super.key, required this.controller});
  final VpnController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final state = controller.state;
      final on = state.desired == Desired.on;
      final dark = Theme.of(context).brightness == Brightness.dark;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final content = Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Semantics(header: true, child: const Text('DUCT–TAPE\nVPN',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                letterSpacing: 2, height: 1.3))),
            IconButton(tooltip: 'Setup and settings',
              icon: const Icon(Icons.more_horiz),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Settings(controller: controller)))),
          ]),
          Padding(padding: const EdgeInsets.symmetric(vertical: 56),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('A private way home.', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 44),
              Semantics(button: true, toggled: on, label: 'VPN',
                value: on ? 'ON requested' : 'OFF',
                hint: state.paired ? 'Toggle connection' : 'Pair in settings first',
                child: AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
                  width: 184, height: 184,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    border: Border.all(width: 1.5,
                      color: on ? const Color(0xff507763) : dark ? const Color(0xff64736c) : const Color(0xff87958c)),
                    color: on ? (dark ? const Color(0xff263e33) : const Color(0xffe1e8de)) : Colors.transparent),
                  child: ExcludeSemantics(child: TextButton(
                    style: TextButton.styleFrom(shape: const CircleBorder(),
                      foregroundColor: dark ? const Color(0xffeff2e9) : const Color(0xff243c30)),
                    onPressed: state.paired && state.nativeAvailable && !controller.busy ? controller.toggle : null,
                    child: Text(on ? 'ON' : 'OFF', style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w400, letterSpacing: 1)),
                  )),
                ),
              ),
              const SizedBox(height: 28),
              Semantics(liveRegion: true, child: Text(state.label(DateTime.now()),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 15))),
              if (controller.error != null)
                Padding(padding: const EdgeInsets.only(top: 12),
                  child: Text(controller.error!, textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(
            state.paired ? 'Your device. Your connection. Your home.' : 'Pair once. Then make yourself at home.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ],
      );
      return Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Padding(padding: const EdgeInsets.fromLTRB(28, 32, 28, 20), child: content)),
        )),
      ))));
    },
  );
}
