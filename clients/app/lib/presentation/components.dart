import 'dart:ui';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

class AppColors {
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color canvas(BuildContext c) =>
      dark(c) ? Colors.black : const Color(0xfff5f5f7);
  static Color surface(BuildContext c) =>
      dark(c) ? const Color(0xff1c1c1e) : Colors.white;
  static Color ink(BuildContext c) =>
      dark(c) ? Colors.white : const Color(0xff1d1d1f);
  static Color secondary(BuildContext c) =>
      dark(c) ? const Color(0xffaeaeb2) : const Color(0xff636366);
  static Color blue(BuildContext c) =>
      dark(c) ? const Color(0xff2997ff) : const Color(0xff0066cc);
}

class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 28});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface(context).withValues(alpha: .82),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: AppColors.ink(context).withValues(alpha: .07),
          ),
        ),
        child: child,
      ),
    ),
  );
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
  });
  final String? title, footer;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondary(context),
              ),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ColoredBox(
            color: AppColors.surface(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 1,
                        thickness: .5,
                        color: AppColors.secondary(context)
                            .withValues(alpha: .2),
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.secondary(context),
              ),
            ),
          ),
      ],
    ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 23, color: AppColors.blue(context)),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondary(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 12),
              Icon(
                CupertinoIcons.chevron_right,
                size: 15,
                color: AppColors.secondary(context),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class GroupField extends StatelessWidget {
  const GroupField({
    super.key,
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.maxLength,
    this.numeric = false,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final int? maxLength;
  final bool numeric;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      maxLength: maxLength,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        labelText: label,
        border: InputBorder.none,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );
}
