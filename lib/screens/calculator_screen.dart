import 'package:flutter/material.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = '';
  String _result = '0';
  final List<Map<String, String>> _history = [];

  void _onButtonTap(String value) {
    setState(() {
      if (value == 'C') {
        _expression = '';
        _result = '0';
      } else if (value == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (value == '=') {
        _calculate();
      } else {
        _expression += value;
      }
    });
  }

  void _calculate() {
    try {
      final expr = _expression.replaceAll('×', '*').replaceAll('÷', '/');
      final result = _eval(expr);
      final resultStr = result == result.toInt().toDouble()
          ? result.toInt().toString()
          : result.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');

      _history.insert(0, {
        'expression': _expression,
        'result': resultStr,
      });

      _result = resultStr;
      _expression = resultStr;
    } catch (e) {
      _result = 'Error';
      _expression = '';
    }
  }

  double _eval(String expr) {
    while (expr.contains('(')) {
      expr = expr.replaceAllMapped(
        RegExp(r'\(([^()]+)\)'),
        (m) => _evalBasic(m.group(1)!).toString(),
      );
    }
    return _evalBasic(expr);
  }

  double _evalBasic(String expr) {
    final tokens = <String>[];
    var current = '';
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if ((c == '+' || c == '-') && i > 0 && expr[i - 1] != '*' && expr[i - 1] != '/') {
        tokens.add(current);
        current = c;
      } else {
        current += c;
      }
    }
    tokens.add(current);

    var result = 0.0;
    var op = '+';
    for (final token in tokens) {
      if (token == '+' || token == '-') {
        op = token;
      } else {
        final val = _evalMulDiv(token);
        result = op == '+' ? result + val : result - val;
      }
    }
    return result;
  }

  double _evalMulDiv(String expr) {
    final tokens = <String>[];
    var current = '';
    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == '*' || c == '/') {
        tokens.add(current);
        tokens.add(c);
        current = '';
      } else {
        current += c;
      }
    }
    tokens.add(current);

    var result = double.parse(tokens[0]);
    var i = 1;
    while (i < tokens.length) {
      final op = tokens[i];
      final val = double.parse(tokens[i + 1]);
      result = op == '*' ? result * val : result / val;
      i += 2;
    }
    return result;
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (ctx, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).textTheme.bodySmall?.color?.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  Text('History', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${_history.length} calculations', style: Theme.of(ctx).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 48, color: Theme.of(ctx).textTheme.bodySmall?.color?.withAlpha(60)),
                          const SizedBox(height: 12),
                          Text('No calculations yet', style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: _history.length,
                      itemBuilder: (ctx, i) {
                        final item = _history[i];
                        return ListTile(
                          dense: true,
                          title: Text(item['expression']!, style: const TextStyle(fontSize: 15)),
                          subtitle: Text('= ${item['result']}', style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.primary)),
                          onTap: () {
                            setState(() => _expression = item['result']!);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCloudSyncDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.primary, size: 32),
        title: const Text('Sync to Cloud'),
        content: const Text(
          'Your calculations are stored locally. Enable cloud sync to access your history across devices.\n\nAre you sure you want to sync your calculations to the cloud?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cloud sync coming soon'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.cloud_upload_outlined, size: 18),
            label: const Text('Enable Sync'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 22),
            onPressed: _showHistory,
            tooltip: 'History',
          ),
          IconButton(
            icon: Icon(Icons.cloud_off, size: 22, color: Theme.of(context).textTheme.bodySmall?.color),
            onPressed: _showCloudSyncDialog,
            tooltip: 'Cloud sync',
          ),
        ],
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          // Display
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _expression.isEmpty ? '0' : _expression,
                    style: TextStyle(fontSize: 28, color: Theme.of(context).textTheme.bodySmall?.color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result,
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.w300, color: gold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Buttons
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildRow(['C', '()', '%', '÷'], surface, gold),
                  const SizedBox(height: 8),
                  _buildRow(['7', '8', '9', '×'], surface, gold),
                  const SizedBox(height: 8),
                  _buildRow(['4', '5', '6', '-'], surface, gold),
                  const SizedBox(height: 8),
                  _buildRow(['1', '2', '3', '+'], surface, gold),
                  const SizedBox(height: 8),
                  _buildRow(['⌫', '0', '.', '='], surface, gold),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> buttons, Color surface, Color gold) {
    return Expanded(
      child: Row(
        children: buttons.map((btn) {
          final isOp = ['÷', '×', '-', '+', '='].contains(btn);
          final isSpecial = ['C', '()', '%', '⌫'].contains(btn);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => _onButtonTap(btn),
                child: Container(
                  decoration: BoxDecoration(
                    color: isOp ? gold : isSpecial ? surface.withAlpha(120) : surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      btn,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: isOp ? Theme.of(context).colorScheme.surface : Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
