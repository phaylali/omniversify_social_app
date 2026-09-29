import 'package:flutter/material.dart';

import '../services/privacy_service.dart';

/// Settings → Privacy: who gets to see what you're reading or playing.
///
/// The three permanent audiences live here; custom lists of people (Friends,
/// School, Work, Trips) will slot in underneath once lists can be built.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gold = cs.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ValueListenableBuilder<ShareAudience>(
        valueListenable: PrivacyService.instance.audience,
        builder: (context, current, _) {
          return RadioGroup<ShareAudience>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) PrivacyService.instance.set(value);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _header(context, 'WHO CAN SEE YOUR ACTIVITY'),
                for (final option in ShareAudience.values)
                  RadioListTile<ShareAudience>(
                    value: option,
                    title: Row(
                      children: [
                        Icon(option.icon, size: 17, color: gold),
                        const SizedBox(width: 10),
                        Text(
                          option.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (option == current) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: gold.withAlpha(35),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: gold.withAlpha(120)),
                            ),
                            child: Text(
                              'ON',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w800,
                                color: gold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      option.blurb,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withAlpha(150),
                      ),
                    ),
                    dense: true,
                    activeColor: gold,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: gold.withAlpha(12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: gold.withAlpha(60)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(current.icon, size: 16, color: gold),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Right now your music and books are shared with: '
                            '${current.label.toLowerCase()}.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: cs.onSurface.withAlpha(180),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _header(context, 'SPECIFIC PEOPLE'),
                ListTile(
                  leading: Icon(
                    Icons.manage_accounts_outlined,
                    size: 22,
                    color: cs.onSurface.withAlpha(90),
                  ),
                  title: Text(
                    'Custom',
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurface.withAlpha(120),
                    ),
                  ),
                  subtitle: Text(
                    'Pick from your lists — Friends, School, Work, Trips. '
                    'Lists fill in as you build them.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withAlpha(110),
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SOON',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withAlpha(130),
                      ),
                    ),
                  ),
                  enabled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'This covers the music player and the books & comics '
                    'reader — whatever you\'re listening to or reading is '
                    'shared at the level chosen above.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: cs.onSurface.withAlpha(130),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 11,
          letterSpacing: 0.5,
          color: Theme.of(context).textTheme.bodySmall?.color,
        ),
      ),
    );
  }
}
