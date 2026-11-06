// Shows a "Still there?" screen after 5 seconds without any interaction, and
// hides it again as soon as you tap, move the mouse, scroll or press a key.
//
// To run it, generate the platform folders once (git ignores them), then run:
//
//   cd example
//   flutter create .
//   flutter run

import 'package:flutter/material.dart';
import 'package:idle_detector/idle_detector.dart';

void main() => runApp(const IdleDetectorExampleApp());

/// How long the user must be inactive before the "Still there?" screen shows.
///
/// Kept short so the demo is quick to try. Real apps usually use minutes.
const Duration kIdleTime = Duration(seconds: 5);

/// Shows a "Still there?" screen over the whole app when the user goes idle,
/// and hides it as soon as they interact again.
class IdleDetectorExampleApp extends StatefulWidget {
  /// Creates the example app.
  const IdleDetectorExampleApp({super.key});

  @override
  State<IdleDetectorExampleApp> createState() => _IdleDetectorExampleAppState();
}

class _IdleDetectorExampleAppState extends State<IdleDetectorExampleApp> {
  final IdleDetectorController _idleController = IdleDetectorController();
  final List<String> _events = <String>[];
  bool _isIdle = false;
  bool _enabled = true;

  void _log(String event) {
    final now = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final time =
        '${twoDigits(now.hour)}:${twoDigits(now.minute)}:'
        '${twoDigits(now.second)}';
    _events.insert(0, '$time  $event');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IdleDetector example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      // Wrapping the navigator through `builder` means taps on every page,
      // dialog and bottom sheet count as activity.
      builder: (context, child) => IdleDetector(
        idleTime: kIdleTime,
        enabled: _enabled,
        controller: _idleController,
        onIdle: () => setState(() {
          _isIdle = true;
          _log('Went idle');
        }),
        onActive: () => setState(() {
          _isIdle = false;
          _log('Became active');
        }),
        child: Stack(
          children: [
            // Hide the app from screen readers while the overlay covers it.
            ExcludeSemantics(excluding: _isIdle, child: child!),
            // The overlay is inside the IdleDetector, so tapping it (or moving
            // the mouse, or pressing a key) counts as activity and hides it.
            // System keys and back navigation still reach the app and the
            // platform as usual: Back still closes a dialog behind the overlay.
            if (_isIdle) _StillThereOverlay(onContinue: _idleController.reset),
          ],
        ),
      ),
      home: _HomePage(
        enabled: _enabled,
        events: _events,
        onEnabledChanged: (value) => setState(() {
          _enabled = value;
          _isIdle = false;
          _log(value ? 'Detection enabled' : 'Detection disabled');
        }),
        // Typing on an on-screen keyboard doesn't send key events, so report
        // it to the detector by hand.
        onTyping: _idleController.reset,
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.enabled,
    required this.events,
    required this.onEnabledChanged,
    required this.onTyping,
  });

  final bool enabled;
  final List<String> events;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onTyping;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IdleDetector example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Stop touching, scrolling, moving the mouse and typing for '
            '${kIdleTime.inSeconds} seconds to go idle.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Idle detection enabled'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Type here',
              helperText: 'Typing keeps you active, even on a phone keyboard.',
            ),
            onChanged: (_) => onTyping(),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: const Text('Taps inside dialogs count too.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Open a dialog'),
          ),
          const SizedBox(height: 24),
          Text('Events', style: Theme.of(context).textTheme.titleMedium),
          if (events.isEmpty) const Text('Nothing yet.'),
          for (final event in events) Text(event),
        ],
      ),
    );
  }
}

class _StillThereOverlay extends StatefulWidget {
  const _StillThereOverlay({required this.onContinue});

  /// Called when a screen reader user activates the overlay.
  final VoidCallback onContinue;

  @override
  State<_StillThereOverlay> createState() => _StillThereOverlayState();
}

class _StillThereOverlayState extends State<_StillThereOverlay> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Still there overlay');

  @override
  void initState() {
    super.initState();
    // Take keyboard focus while the overlay is shown, in a focus scope of its
    // own (see build). The key press that dismisses the overlay then can't
    // activate the widget that was focused behind it, and Tab can't move focus
    // there. (If the key is held down, its repeats reach that widget once the
    // overlay is gone, like any other held key.)
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Positioned.fill(
      child: FocusScope(
        child: Focus(
          focusNode: _focusNode,
          child: Material(
            color: Colors.black87,
            // Present the overlay to screen readers like a new screen, so they
            // announce it and move their focus to it.
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Still there?',
              // A screen reader moving its focus onto the overlay doesn't end
              // the idle period, so give screen reader users something to
              // activate.
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  onTap: widget.onContinue,
                  child: _buildMessage(textTheme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bedtime_outlined, size: 64, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            'Still there?',
            style: textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap anywhere, move the mouse or press a key to continue.',
            style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
