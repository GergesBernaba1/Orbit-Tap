import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../state/vault_controller.dart';

class DecoyGameScreen extends StatefulWidget {
  const DecoyGameScreen({
    required this.controller,
    super.key,
  });

  final VaultController controller;

  @override
  State<DecoyGameScreen> createState() => _DecoyGameScreenState();
}

class _DecoyGameScreenState extends State<DecoyGameScreen> {
  final TextEditingController _tagController = TextEditingController();
  final Random _random = Random();

  Timer? _timer;
  String _playerTag = 'Guest';
  int _score = 0;
  int _bestScore = 0;
  double _targetX = 40;
  double _targetY = 40;
  double _timeLeft = 20;
  bool _running = false;

  @override
  void dispose() {
    _timer?.cancel();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _submitTagOrSecret() async {
    final text = _tagController.text.trim();

    if (text.isNotEmpty) {
      final openedVault = await widget.controller.tryDecoyCode(text);
      if (openedVault || !mounted) {
        return;
      }

      setState(() {
        _playerTag = text;
      });
    }

    _startRound();
    _tagController.clear();
  }

  void _startRound() {
    _timer?.cancel();
    setState(() {
      _score = 0;
      _timeLeft = 20;
      _running = true;
    });

    _moveTarget();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _timeLeft -= 0.1;
        if (_timeLeft <= 0) {
          _timeLeft = 0;
          _running = false;
          _bestScore = max(_bestScore, _score);
          timer.cancel();
        }
      });
    });
  }

  void _moveTarget() {
    setState(() {
      _targetX = 12 + _random.nextDouble() * 220;
      _targetY = 12 + _random.nextDouble() * 280;
    });
  }

  void _hitTarget() {
    if (!_running) {
      return;
    }

    setState(() {
      _score += 1;
      _bestScore = max(_bestScore, _score);
      _timeLeft = min(20, _timeLeft + 0.35);
    });
    _moveTarget();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF3A506B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orbit Tap',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Catch the moving core before the timer runs out.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _ScoreCard(label: 'Player', value: _playerTag),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ScoreCard(label: 'Score', value: '$_score'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ScoreCard(label: 'Best', value: '$_bestScore'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ScoreCard(
                  label: 'Time',
                  value: '${_timeLeft.toStringAsFixed(1)}s',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxX = max(12.0, constraints.maxWidth - 84);
                      final maxY = max(12.0, constraints.maxHeight - 84);
                      final safeTargetX = _targetX.clamp(12.0, maxX) as double;
                      final safeTargetY = _targetY.clamp(12.0, maxY) as double;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(28),
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.10),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutBack,
                              left: safeTargetX,
                              top: safeTargetY,
                              child: GestureDetector(
                                onTap: _hitTarget,
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6FFFE9), Color(0xFF5BC0BE)],
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x886FFFE9),
                                        blurRadius: 22,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.blur_on,
                                    color: Color(0xFF0B132B),
                                    size: 34,
                                  ),
                                ),
                              ),
                            ),
                            if (!_running)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Tap Start Run to begin.\nUse your player tag any time to switch profiles.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                          height: 1.4,
                                        ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tagController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _submitTagOrSecret(),
                  decoration: InputDecoration(
                    labelText: 'Player tag',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: 'Enter nickname or load code',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.controller.busy ? null : _submitTagOrSecret,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6FFFE9),
                      foregroundColor: const Color(0xFF0B132B),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      widget.controller.busy
                          ? 'Checking...'
                          : (_running ? 'Restart Run' : 'Start Run'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white60,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
