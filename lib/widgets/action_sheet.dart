import 'package:flutter/material.dart';

/// How a row reads: the destructive ones (block, report) stay red like the
/// rest of the app's warnings.
enum ActionSheetTone { normal, destructive }

/// One tappable row of an action sheet.
class ActionSheetItem {
  const ActionSheetItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tone = ActionSheetTone.normal,
  });

  final IconData icon;
  final String title;

  /// Second line explaining what the action actually does.
  final String? subtitle;
  final VoidCallback? onTap;
  final ActionSheetTone tone;
}

/// The bottom sheet every `⋮` menu opens: grab handle, who it is about,
/// then icon + title + subtitle rows.
///
/// The scrolls menu and the post menu both use it so they can never drift
/// apart again — each closes the sheet first, then runs its own action so
/// confirmations land on the screen behind it.
void showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData icon = Icons.more_horiz,
  required List<ActionSheetItem> items,
}) {
  final cs = Theme.of(context).colorScheme;
  final gold = cs.primary;

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      // Long menus (or large text) scroll instead of overflowing the sheet.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, color: gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withAlpha(150),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final item in items)
                ListTile(
                  leading: Icon(
                    item.icon,
                    size: 20,
                    color: item.tone == ActionSheetTone.destructive
                        ? Colors.red
                        : gold,
                  ),
                  title: Text(
                    item.title,
                    style: item.tone == ActionSheetTone.destructive
                        ? const TextStyle(color: Colors.red)
                        : null,
                  ),
                  subtitle: item.subtitle == null
                      ? null
                      : Text(
                          item.subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withAlpha(140),
                          ),
                        ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    item.onTap?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Confirmation shown once an action sheet has closed — optionally with an
/// `UNDO` escape hatch, as the mute actions all have.
void showActionNotice(
  BuildContext context,
  String message, {
  String? undoLabel,
  VoidCallback? onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: undoLabel == null ? 3 : 4),
        behavior: SnackBarBehavior.floating,
        action: undoLabel == null
            ? null
            : SnackBarAction(label: undoLabel, onPressed: onUndo ?? () {}),
      ),
    );
}
