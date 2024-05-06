library idle_detector;

import 'dart:async';
import 'package:flutter/material.dart';

class IdleDetector extends StatefulWidget {
  final Duration idleTime;

  final Function? onIdle;
  final Widget child;

  const IdleDetector({
    super.key,
    required this.idleTime,
    this.onIdle,
    required this.child,
  });

  @override
  State<IdleDetector> createState() => _IdleDetectorState();
}

class _IdleDetectorState extends State<IdleDetector> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(widget.idleTime, () {
      if (widget.onIdle != null) {
        widget.onIdle!();
      }
    });
  }

  void handleUserInteraction() {
    _resetTimer();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        handleUserInteraction();
      },
      onPanDown: (details) {
        handleUserInteraction();
      },
      onHorizontalDragEnd: (details) {
        handleUserInteraction();
      },
      onVerticalDragEnd: (details) {
        handleUserInteraction();
      },
      child: widget.child,
    );
  }
}
