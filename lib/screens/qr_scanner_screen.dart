import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _controller;
  bool _hasPermission = false;
  bool _checkingPermission = true;
  bool _isProcessing = false;
  String _denialMessage = '';
  final List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    setState(() {
      _checkingPermission = true;
      _denialMessage = '';
    });

    var status = await Permission.camera.status;

    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isPermanentlyDenied) {
      setState(() {
        _hasPermission = false;
        _checkingPermission = false;
        _denialMessage = 'Camera permission was permanently denied. Please enable it in your device settings.';
      });
      return;
    }

    if (status.isGranted || status.isLimited) {
      _controller?.dispose();
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
      );

      setState(() {
        _hasPermission = true;
        _checkingPermission = false;
      });

      // Start camera after the widget tree is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null) {
          _controller!.start();
        }
      });
    } else {
      setState(() {
        _hasPermission = false;
        _checkingPermission = false;
        _denialMessage = 'Camera permission is required to scan QR codes.';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() {
      _isProcessing = true;
      _history.insert(0, {
        'value': barcode.rawValue!,
        'type': barcode.format.name,
        'time': DateTime.now(),
      });
    });
    _controller?.stop();

    _showResultDialog(barcode.rawValue!, barcode.format.name);
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
                  Text('Scan History', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.cloud_off, size: 20, color: Theme.of(ctx).textTheme.bodySmall?.color),
                    onPressed: () => _showCloudSyncDialog(ctx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Text('${_history.length} scans', style: Theme.of(ctx).textTheme.bodySmall),
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
                          Icon(Icons.qr_code_scanner, size: 48, color: Theme.of(ctx).textTheme.bodySmall?.color?.withAlpha(60)),
                          const SizedBox(height: 12),
                          Text('No scans yet', style: TextStyle(color: Theme.of(ctx).textTheme.bodySmall?.color)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: _history.length,
                      itemBuilder: (ctx, i) {
                        final item = _history[i];
                        final dt = item['time'] as DateTime;
                        final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        final dateStr = '${dt.day}/${dt.month}/${dt.year}';
                        final isUrl = (item['value'] as String).startsWith('http');
                        return ListTile(
                          leading: Icon(
                            isUrl ? Icons.link : Icons.qr_code,
                            size: 20,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                          title: Text(
                            item['value'],
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$timeStr · $dateStr · ${item['type']}',
                            style: TextStyle(fontSize: 11, color: Theme.of(ctx).textTheme.bodySmall?.color),
                          ),
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item['value']));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
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

  void _showCloudSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.primary, size: 32),
        title: const Text('Sync to Cloud'),
        content: const Text(
          'Your scan history is stored locally. Enable cloud sync to access it across devices.\n\nAre you sure you want to sync your scan history to the cloud?',
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

  void _showResultDialog(String value, String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          value.startsWith('http') ? Icons.link : Icons.qr_code,
          color: Theme.of(context).colorScheme.primary,
          size: 32,
        ),
        title: const Text('QR Code Scanned'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $type', style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(value, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resumeScanner();
            },
            child: const Text('Scan Again'),
          ),
          if (value.startsWith('http'))
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final uri = Uri.parse(value);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                _resumeScanner();
              },
              child: const Text('Open Link'),
            ),
        ],
      ),
    );
  }

  void _resumeScanner() {
    setState(() => _isProcessing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller != null) {
        _controller!.start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    if (_checkingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Scanner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt_outlined, size: 64, color: gold.withAlpha(80)),
                const SizedBox(height: 16),
                Text('Camera Permission Required', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(
                  _denialMessage.isEmpty
                      ? 'This app needs camera access to scan QR codes. Please grant camera permission.'
                      : _denialMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _requestPermission,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Grant Permission'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 22),
            onPressed: _showHistory,
          ),
          IconButton(
            icon: const Icon(Icons.flash_on_outlined),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Scanning frame
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: gold.withAlpha(150), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Hint
          Positioned(
            bottom: 80,
            left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(150),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Point camera at a QR code', style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ),

          ..._buildCornerMarkers(context),
        ],
      ),
    );
  }

  List<Widget> _buildCornerMarkers(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;
    const size = 250.0;
    const markerLen = 30.0;
    const borderWidth = 3.0;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return [
      Positioned(
        top: (screenH - size) / 2,
        left: (screenW - size) / 2,
        child: CustomPaint(size: const Size(markerLen, markerLen), painter: _CornerPainter(gold, borderWidth, _Corner.topLeft)),
      ),
      Positioned(
        top: (screenH - size) / 2,
        right: (screenW - size) / 2,
        child: CustomPaint(size: const Size(markerLen, markerLen), painter: _CornerPainter(gold, borderWidth, _Corner.topRight)),
      ),
      Positioned(
        bottom: (screenH - size) / 2,
        left: (screenW - size) / 2,
        child: CustomPaint(size: const Size(markerLen, markerLen), painter: _CornerPainter(gold, borderWidth, _Corner.bottomLeft)),
      ),
      Positioned(
        bottom: (screenH - size) / 2,
        right: (screenW - size) / 2,
        child: CustomPaint(size: const Size(markerLen, markerLen), painter: _CornerPainter(gold, borderWidth, _Corner.bottomRight)),
      ),
    ];
  }
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final _Corner corner;

  _CornerPainter(this.color, this.strokeWidth, this.corner);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    switch (corner) {
      case _Corner.topLeft:
        canvas.drawLine(Offset(0, size.height), Offset.zero, paint);
        canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
        break;
      case _Corner.topRight:
        canvas.drawLine(Offset(0, 0), Offset(size.width, 0), paint);
        canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
        break;
      case _Corner.bottomLeft:
        canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
        canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint);
        break;
      case _Corner.bottomRight:
        canvas.drawLine(Offset(size.width, 0), Offset(size.width, size.height), paint);
        canvas.drawLine(Offset(size.width, size.height), Offset(0, size.height), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
