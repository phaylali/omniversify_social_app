import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

class FlashlightScreen extends StatefulWidget {
  const FlashlightScreen({super.key});

  @override
  State<FlashlightScreen> createState() => _FlashlightScreenState();
}

class _FlashlightScreenState extends State<FlashlightScreen> {
  bool _isOn = false;
  CameraController? _controller;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _hasPermission = false);
      return;
    }
    if (mounted) setState(() => _hasPermission = true);

    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(back, ResolutionPreset.low, enableAudio: false);
      await _controller!.initialize();
      _controller!.setFlashMode(FlashMode.off);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_isOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      if (mounted) setState(() => _isOn = !_isOn);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Flashlight')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_hasPermission) ...[
              Icon(Icons.flashlight_off, size: 64, color: cs.onSurface.withAlpha(80)),
              const SizedBox(height: 16),
              Text('Camera permission is required for flashlight',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface.withAlpha(150))),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () async {
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ] else ...[
              GestureDetector(
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOn ? cs.primary : cs.surfaceContainerHighest,
                    boxShadow: _isOn
                        ? [BoxShadow(color: cs.primary.withAlpha(80), blurRadius: 40, spreadRadius: 10)]
                        : [],
                  ),
                  child: Icon(
                    _isOn ? Icons.flashlight_on : Icons.flashlight_off,
                    size: 64,
                    color: _isOn ? cs.onPrimary : cs.onSurface.withAlpha(120),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isOn ? 'ON' : 'OFF',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _isOn ? cs.primary : cs.onSurface.withAlpha(120),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to toggle',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withAlpha(100)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
