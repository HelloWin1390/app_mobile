import 'dart:async';
import 'package:flutter/material.dart';
import '../services/command_service.dart';

class DualMotorSlider extends StatefulWidget {
  const DualMotorSlider({super.key});
  @override State<DualMotorSlider> createState() => _DualMotorSliderState();
}

class _DualMotorSliderState extends State<DualMotorSlider> {
  double _left  = 0;
  double _right = 0;
  String _leftLabel  = 'STOP';
  String _rightLabel = 'STOP';
  Timer? _timer;

  void _startLoop() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _sendCombined());
  }

  void _stopLoop() {
    _timer?.cancel();
    _timer = null;
  }

  void _sendCombined() {
    final l = _left;
    final r = _right;
    if      (l >  0.2 && r >  0.2) CommandService.send('forward');
    else if (l < -0.2 && r < -0.2) CommandService.send('backward');
    else if (l >  0.2 && r.abs() <= 0.2) CommandService.send('left-forward');
    else if (r >  0.2 && l.abs() <= 0.2) CommandService.send('right-forward');
    else CommandService.send('stop');
  }

  String _label(double v) {
    if (v >  0.2) return 'FWD';
    if (v < -0.2) return 'BWD';
    return 'STOP';
  }

  void _onRelease() {
    setState(() { _left = 0; _right = 0; _leftLabel = 'STOP'; _rightLabel = 'STOP'; });
    _stopLoop();
    CommandService.send('stop');
  }

  Widget _buildSlider({
    required double value,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    const color = Color(0xFF4F98A3);
    final trackH = 220.0;
    final thumbY = (1 - (value + 1) / 2) * trackH;

    return Column(children: [
      Text(label,
        style: const TextStyle(
          color: Color(0xFF4F98A3),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        onVerticalDragUpdate: (d) {
          final delta = -d.delta.dy / (trackH / 2);
          onChanged((value + delta).clamp(-1.0, 1.0));
        },
        onVerticalDragEnd: (_) => _onRelease(),
        child: Container(
          width: 60,
          height: trackH,
          decoration: BoxDecoration(
            color: const Color(0xFF1C1B19),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF393836)),
          ),
          child: Stack(clipBehavior: Clip.antiAlias, children: [
            // Track line
            Center(
              child: Container(
                width: 3,
                height: trackH,
                color: const Color(0xFF393836),
              ),
            ),
            // Active fill
            if (value.abs() > 0.05)
              Positioned(
                top: value >= 0 ? trackH / 2 - value * trackH / 2 : trackH / 2,
                left: 0, right: 0,
                height: value.abs() * trackH / 2,
                child: Center(
                  child: Container(
                    width: 3,
                    color: color,
                  ),
                ),
              ),
            // Thumb
            Positioned(
              top: thumbY - 20,
              left: 0, right: 0,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value.abs() > 0.05 ? color : const Color(0xFF2D2C2A),
                    boxShadow: value.abs() > 0.05
                      ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 14)]
                      : [],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildSlider(
          value: _left,
          label: 'Л: $_leftLabel',
          onChanged: (v) {
            setState(() { _left = v; _leftLabel = _label(v); });
            if (!(_timer?.isActive ?? false)) _startLoop();
          },
        ),
        _buildSlider(
          value: _right,
          label: 'П: $_rightLabel',
          onChanged: (v) {
            setState(() { _right = v; _rightLabel = _label(v); });
            if (!(_timer?.isActive ?? false)) _startLoop();
          },
        ),
      ],
    );
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}