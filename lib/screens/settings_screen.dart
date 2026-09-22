import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omniversify_widget/omniversify_widget.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(catppuccinThemeProvider);
    final provider = ref.read(catppuccinThemeProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    final themes = CatppuccinPalette.all;
    final accents = themeState.flavorIndex < CatppuccinPalette.all.length
        ? CatppuccinPalette.all[themeState.flavorIndex].accentOptions
        : CatppuccinPalette.all[4].accentOptions;
    final accentNames = themeState.flavorIndex < CatppuccinPalette.all.length
        ? CatppuccinPalette.all[themeState.flavorIndex].accentNames
        : CatppuccinPalette.all[4].accentNames;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(context, 'APPEARANCE'),
          const SizedBox(height: 4),
          _sectionHeader(context, 'Theme', small: true),
          ...List.generate(themes.length, (i) {
            final palette = themes[i];
            return RadioListTile<int>(
              value: i,
              groupValue: themeState.flavorIndex,
              onChanged: (v) => provider.setFlavor(v!),
              title: Text(palette.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(palette.description, style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(120))),
              dense: true,
              activeColor: cs.primary,
            );
          }),
          const SizedBox(height: 8),
          _sectionHeader(context, 'Accent Color', small: true),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(accents.length, (i) {
                final color = accents[i];
                final name = i < accentNames.length ? accentNames[i] : 'Accent $i';
                final selected = themeState.accentIndex == i;
                return GestureDetector(
                  onTap: () => provider.setAccent(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? cs.onSurface : Colors.transparent,
                            width: 2,
                          ),
                          boxShadow: selected
                              ? [BoxShadow(color: color.withAlpha(80), blurRadius: 8)]
                              : null,
                        ),
                        child: selected
                            ? Icon(Icons.check, color: cs.onPrimary, size: 20)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: TextStyle(fontSize: 10, color: cs.onSurface.withAlpha(selected ? 200 : 120))),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'GENERAL'),
          _tile(
            context,
            icon: Icons.language_outlined,
            title: 'Language',
            subtitle: 'English (US)',
            onTap: () {},
          ),
          _tile(
            context,
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            subtitle: 'Push, email',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'ACCOUNT'),
          _tile(
            context,
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Email, password, privacy',
            onTap: () {},
          ),
          _tile(
            context,
            icon: Icons.cloud_off_outlined,
            title: 'Cloud Sync',
            subtitle: 'Manage data sync',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'SUPPORT'),
          _tile(
            context,
            icon: Icons.help_outline,
            title: 'Help & Support',
            onTap: () {},
          ),
          _tile(
            context,
            icon: Icons.feedback_outlined,
            title: 'Send Feedback',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _sectionHeader(context, 'ABOUT'),
          _tile(
            context,
            icon: Icons.info_outline,
            title: 'About Omniversify',
            subtitle: 'Version 1.0.0',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, {bool small = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, small ? 2 : 8, 16, small ? 2 : 4),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: small ? 10 : 11,
        color: Theme.of(context).textTheme.bodySmall?.color,
        letterSpacing: small == false ? 0.5 : 0,
      )),
    );
  }

  Widget _tile(BuildContext context, {required IconData icon, required String title, String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Omniversify',
      applicationVersion: '1.0.0',
      applicationIcon: Icon(Icons.apps, color: Theme.of(context).colorScheme.primary, size: 32),
      children: const [
        Text('A social media app for tracking movies, TV shows, games, books, anime, and more.'),
        SizedBox(height: 12),
        Text('Built with Flutter and the Omniversify Widget design system.'),
      ],
    );
  }
}
