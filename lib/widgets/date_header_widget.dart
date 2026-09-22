import 'package:flutter/material.dart';
import '../services/date_service.dart';

class DateHeader extends StatefulWidget {
  const DateHeader({super.key});

  @override
  State<DateHeader> createState() => _DateHeaderState();
}

class _DateHeaderState extends State<DateHeader> {
  TripleDate? _date;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DateService.fetchToday();
      if (mounted) setState(() { _date = d; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 20, child: Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))));
    }
    if (_date == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 11,
      color: cs.onSurface.withAlpha(150),
      letterSpacing: 0.3,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _calendarChip(context, '${_date!.gregorian.day} ${_date!.gregorian.month.latin}', Icons.calendar_today_outlined, style),
          const SizedBox(width: 6),
          _calendarChip(context, '${_date!.islamic.day} ${_date!.islamic.month.arabic}', null, style, iconUnicode: '\u0639'),
          const SizedBox(width: 6),
          _calendarChip(context, '${_date!.amazigh.day} ${_date!.amazigh.month.tifinagh}', null, style, iconUnicode: '\u2D62'),
        ],
      ),
    );
  }

  Widget _calendarChip(BuildContext context, String text, IconData? icon, TextStyle? style, {String? iconUnicode}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 10, color: cs.primary),
              const SizedBox(width: 3),
            ] else if (iconUnicode != null) ...[
              Text(iconUnicode, style: style?.copyWith(fontSize: 10, color: cs.primary)),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(text, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}
