import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_detector/idle_detector.dart';

const Duration idleTime = Duration(seconds: 10);
const Duration almostIdle = Duration(seconds: 9);
const Duration tick = Duration(seconds: 1);

/// Records the callbacks fired by an [IdleDetector].
class CallbackLog {
  int idle = 0;
  int active = 0;
  final List<String> events = <String>[];

  void onIdle() {
    idle++;
    events.add('idle');
  }

  void onActive() {
    active++;
    events.add('active');
  }
}

/// Pumps an [IdleDetector] that wraps [child] inside a [MaterialApp].
Future<void> pumpDetector(
  WidgetTester tester, {
  required CallbackLog log,
  Widget child = const Center(child: Text('content')),
  Duration idleTime = idleTime,
  bool enabled = true,
  bool detectKeyboardActivity = true,
  IdleDetectorController? controller,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: IdleDetector(
        idleTime: idleTime,
        onIdle: log.onIdle,
        onActive: log.onActive,
        enabled: enabled,
        detectKeyboardActivity: detectKeyboardActivity,
        controller: controller,
        child: child,
      ),
    ),
  );
}

const List<AppLifecycleState> goingToBackground = <AppLifecycleState>[
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

const List<AppLifecycleState> comingToForeground = <AppLifecycleState>[
  AppLifecycleState.hidden,
  AppLifecycleState.inactive,
  AppLifecycleState.resumed,
];

/// Builds [widget] while the app is hidden or paused, the way `runApp`'s
/// warm-up frame does even though frames are otherwise disabled.
Future<void> pumpWhileHidden(WidgetTester tester, Widget widget) {
  tester.binding.attachRootWidget(tester.binding.wrapWithDefaultView(widget));
  tester.binding.scheduleWarmUpFrame();
  return tester.pump();
}

void main() {
  group('countdown', () {
    testWidgets('calls onIdle after idleTime without interaction', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('calls onIdle only once per idle period', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime * 5);
      expect(log.idle, 1);
    });

    testWidgets('works without any callbacks', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IdleDetector(idleTime: idleTime, child: Text('content')),
        ),
      );

      await tester.pump(idleTime);
      await tester.tap(find.text('content'));
      await tester.pump(idleTime);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancels the countdown when removed from the tree', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(idleTime * 2);
      expect(log.idle, 0);
    });

    testWidgets('calls the latest onIdle callback', (tester) async {
      final calls = <String>[];
      Widget build(String name) {
        return MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: () => calls.add(name),
            child: const SizedBox.expand(),
          ),
        );
      }

      await tester.pumpWidget(build('first'));
      await tester.pumpWidget(build('second'));
      await tester.pump(idleTime);
      expect(calls, <String>['second']);
    });

    testWidgets('asserts that idleTime is positive', (tester) async {
      await tester.pumpWidget(
        const IdleDetector(idleTime: Duration.zero, child: SizedBox()),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('asserts that an updated idleTime is positive', (tester) async {
      await tester.pumpWidget(
        const IdleDetector(idleTime: idleTime, child: SizedBox()),
      );
      await tester.pumpWidget(
        const IdleDetector(idleTime: Duration(seconds: -1), child: SizedBox()),
      );
      expect(tester.takeException(), isAssertionError);
    });
  });

  group('pointer activity', () {
    testWidgets('a tap restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await tester.tap(find.text('content'));
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a tap on empty space restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(almostIdle);
      expect(log.idle, 0);
    });

    testWidgets('a tap on a button counts and still reaches the button', (
      tester,
    ) async {
      final log = CallbackLog();
      var presses = 0;
      await pumpDetector(
        tester,
        log: log,
        child: Center(
          child: ElevatedButton(
            onPressed: () => presses++,
            child: const Text('button'),
          ),
        ),
      );

      await tester.pump(almostIdle);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump(almostIdle);
      expect(presses, 1);
      expect(log.idle, 0);
    });

    testWidgets('a long drag keeps the user active and still scrolls', (
      tester,
    ) async {
      final log = CallbackLog();
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await pumpDetector(
        tester,
        log: log,
        child: ListView.builder(
          controller: scrollController,
          itemCount: 200,
          itemBuilder: (context, index) =>
              SizedBox(height: 50, child: Text('item $index')),
        ),
      );

      final gesture = await tester.startGesture(const Offset(400, 500));
      // Drag slowly for 3x the idle time.
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, -5));
        await tester.pump(tick);
      }
      expect(log.idle, 0);
      expect(scrollController.offset, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(idleTime);
      expect(log.idle, 1);
    });

    testWidgets('pressing down counts on its own', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      final gesture = await tester.startGesture(const Offset(5, 5));
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      await gesture.up();
    });

    testWidgets('releasing counts on its own', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      final gesture = await tester.startGesture(const Offset(5, 5));
      await tester.pump(almostIdle);
      await gesture.up();
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a gesture that outlives the detector is ignored', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);
      await tester.pump(idleTime);
      expect(log.events, <String>['idle']);

      // Flutter keeps routing a pointer to the widgets it went down on, even
      // after they leave the tree.
      final gesture = await tester.startGesture(const Offset(5, 5));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.expand()));
      await gesture.moveBy(const Offset(0, 20));
      await gesture.up();
      await tester.pump(idleTime * 2);
      expect(log.events, <String>['idle', 'active']);
    });

    testWidgets('holding a pointer down without moving goes idle', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      final gesture = await tester.startGesture(const Offset(5, 5));
      await tester.pump(idleTime);
      expect(log.idle, 1);
      await gesture.up();
    });

    testWidgets('mouse movement restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);

      await tester.pump(almostIdle);
      await mouse.moveTo(const Offset(50, 50));
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a mouse wheel scroll restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.addPointer(location: const Offset(50, 50)),
      );

      await tester.pump(almostIdle);
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      await tester.sendEventToBinding(pointer.removePointer());
    });

    testWidgets('a trackpad gesture restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(const Offset(50, 50));
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await trackpad.panZoomUpdate(
        const Offset(50, 50),
        pan: const Offset(0, 20),
      );
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await trackpad.panZoomEnd();
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('pointer events outside the child do not count', (
      tester,
    ) async {
      final log = CallbackLog();
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                height: 100,
                child: IdleDetector(
                  idleTime: idleTime,
                  onIdle: log.onIdle,
                  child: const SizedBox.expand(),
                ),
              ),
              const Expanded(child: SizedBox.expand()),
            ],
          ),
        ),
      );

      await tester.pump(almostIdle);
      await tester.tapAt(const Offset(5, 300));
      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('does not block widgets behind it in a Stack', (tester) async {
      final log = CallbackLog();
      var backgroundTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => backgroundTaps++,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
              Positioned.fill(
                child: IdleDetector(
                  idleTime: idleTime,
                  onIdle: log.onIdle,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pump(almostIdle);
      await tester.tapAt(const Offset(100, 100));
      await tester.pump(almostIdle);
      expect(backgroundTaps, 1);
      expect(log.idle, 0);
    });
  });

  group('keyboard activity', () {
    testWidgets('a key press restarts the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('key presses still reach focused widgets', (tester) async {
      final log = CallbackLog();
      final received = <LogicalKeyboardKey>[];
      await pumpDetector(
        tester,
        log: log,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              received.add(event.logicalKey);
            }
            return KeyEventResult.handled;
          },
          child: const SizedBox.expand(),
        ),
      );
      await tester.pump();

      await tester.pump(almostIdle);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(almostIdle);
      expect(received, <LogicalKeyboardKey>[LogicalKeyboardKey.keyA]);
      expect(log.idle, 0);
    });

    testWidgets('does not mark key events as handled', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      // Nothing else in the app handles this key, so it must be reported back
      // to the platform as unhandled.
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ), isFalse);
      expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ), isFalse);
    });

    testWidgets('is ignored when detectKeyboardActivity is false', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log, detectKeyboardActivity: false);

      await tester.pump(almostIdle);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('detectKeyboardActivity can be toggled', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log, detectKeyboardActivity: false);
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await pumpDetector(tester, log: log, detectKeyboardActivity: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a removed detector ignores key events', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);
      await tester.pumpWidget(const SizedBox());

      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(idleTime);
      expect(log.events, isEmpty);
    });
  });

  group('onActive', () {
    testWidgets('callbacks see the new state and can call reset', (
      tester,
    ) async {
      final controller = IdleDetectorController();
      final seen = <String>[];
      var resetFromOnIdle = true;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            controller: controller,
            onIdle: () {
              seen.add('idle, isIdle: ${controller.isIdle}');
              if (resetFromOnIdle) {
                resetFromOnIdle = false;
                controller.reset();
              }
            },
            onActive: () => seen.add('active, isIdle: ${controller.isIdle}'),
            child: const SizedBox.expand(),
          ),
        ),
      );

      await tester.pump(idleTime);
      expect(seen, <String>['idle, isIdle: true', 'active, isIdle: false']);

      // The reset from onIdle started a new countdown.
      await tester.pump(idleTime);
      expect(seen.last, 'idle, isIdle: true');
      expect(seen, hasLength(3));
    });

    testWidgets('is called on the first interaction after going idle', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      await tester.tap(find.text('content'));
      await tester.pump();
      expect(log.events, <String>['idle', 'active']);

      // More interactions while active do not call onActive again.
      await tester.tap(find.text('content'));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(log.active, 1);
    });

    testWidgets('is not called for interactions before going idle', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.tap(find.text('content'));
      await tester.pump(almostIdle);
      await tester.tap(find.text('content'));
      await tester.pump();
      expect(log.active, 0);
    });

    testWidgets('starts a new countdown that can go idle again', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      await tester.tap(find.text('content'));
      await tester.pump(almostIdle);
      expect(log.idle, 1);

      await tester.pump(tick);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(log.events, <String>['idle', 'active', 'idle', 'active']);
    });

    testWidgets('errors from onActive are reported, not thrown', (
      tester,
    ) async {
      var idleCount = 0;
      final controller = IdleDetectorController();
      await tester.pumpWidget(
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: () => idleCount++,
            onActive: () => throw StateError('boom'),
            controller: controller,
            child: const SizedBox.expand(),
          ),
        ),
      );

      await tester.pump(idleTime);
      // A single activity event, so nothing else restarts the countdown.
      controller.reset();
      expect(tester.takeException(), isStateError);
      await tester.pump(idleTime);
      expect(idleCount, 2);
    });

    testWidgets('errors from onIdle are reported, not thrown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: () => throw StateError('boom'),
            child: const SizedBox.expand(),
          ),
        ),
      );

      await tester.pump(idleTime);
      expect(tester.takeException(), isStateError);
    });
  });

  group('idleTime changes', () {
    testWidgets('restart the countdown with the new duration', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await pumpDetector(tester, log: log, idleTime: idleTime * 2);
      await tester.pump(idleTime * 2 - tick);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('while idle apply after the next interaction', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      await pumpDetector(tester, log: log, idleTime: idleTime * 2);
      await tester.pump(idleTime * 3);
      expect(log.events, <String>['idle']);

      await tester.tap(find.text('content'));
      await tester.pump(idleTime * 2 - tick);
      expect(log.idle, 1);

      await tester.pump(tick);
      expect(log.idle, 2);
    });
  });

  group('enabled', () {
    testWidgets('when false, never goes idle', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log, enabled: false);

      await tester.pump(idleTime * 3);
      await tester.tap(find.text('content'));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump(idleTime * 3);
      expect(log.events, isEmpty);
    });

    testWidgets('disabling stops the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(almostIdle);
      await pumpDetector(tester, log: log, enabled: false);
      await tester.pump(idleTime * 3);
      expect(log.events, isEmpty);
    });

    testWidgets('re-enabling starts a full new countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log, enabled: false);

      await tester.pump(idleTime * 3);
      await pumpDetector(tester, log: log);
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('disabling while idle clears idle without onActive', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      await tester.pump(idleTime);
      expect(controller.isIdle, isTrue);

      await pumpDetector(
        tester,
        log: log,
        controller: controller,
        enabled: false,
      );
      expect(controller.isIdle, isFalse);
      expect(log.events, <String>['idle']);

      await pumpDetector(tester, log: log, controller: controller);
      await tester.tap(find.text('content'));
      await tester.pump();
      expect(log.events, <String>['idle']);
    });

    testWidgets('toggling keeps the child state', (tester) async {
      final log = CallbackLog();
      Widget child() => const Material(child: TextField());

      await pumpDetector(tester, log: log, child: child());
      await tester.enterText(find.byType(TextField), 'kept');
      await pumpDetector(tester, log: log, child: child(), enabled: false);
      await pumpDetector(tester, log: log, child: child());
      expect(find.text('kept'), findsOneWidget);
    });
  });

  group('screen readers', () {
    var nextFocusedNode = 1000;

    /// Reports that a screen reader moved its focus to another node, the way
    /// iOS and Android do.
    Future<void> sendAccessibilityFocus(WidgetTester tester) {
      return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.accessibility.name,
        SystemChannels.accessibility.codec.encodeMessage(<String, Object?>{
          'type': 'didGainFocus',
          'nodeId': nextFocusedNode++,
        }),
        (_) {},
      );
    }

    /// Sends [action] the way the platform does, through the dispatcher.
    void sendSemanticsAction(
      WidgetTester tester,
      Finder finder,
      SemanticsAction action,
    ) {
      tester.binding.platformDispatcher.onSemanticsActionEvent!(
        SemanticsActionEvent(
          type: action,
          viewId: tester.view.viewId,
          nodeId: tester.getSemantics(finder).id,
        ),
      );
    }

    testWidgets('a semantics tap counts and still reaches the button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final log = CallbackLog();
      var presses = 0;
      await pumpDetector(
        tester,
        log: log,
        child: Center(
          child: ElevatedButton(
            onPressed: () => presses++,
            child: const Text('button'),
          ),
        ),
      );

      await tester.pump(almostIdle);
      sendSemanticsAction(
        tester,
        find.byType(ElevatedButton),
        SemanticsAction.tap,
      );
      await tester.pump(almostIdle);
      expect(presses, 1);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      semantics.dispose();
    });

    testWidgets('focus actions keep the user active', (tester) async {
      final semantics = tester.ensureSemantics();
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      // Swiping from item to item, as a screen reader user does to read.
      for (var i = 0; i < 3; i++) {
        await tester.pump(almostIdle);
        sendSemanticsAction(
          tester,
          find.text('content'),
          SemanticsAction.didGainAccessibilityFocus,
        );
      }
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      semantics.dispose();
    });

    testWidgets('focus actions do not end idle, other actions do', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final log = CallbackLog();
      await pumpDetector(
        tester,
        log: log,
        child: Center(
          child: ElevatedButton(onPressed: () {}, child: const Text('button')),
        ),
      );

      await tester.pump(idleTime);
      // Screen readers send these by themselves, for example when the UI shown
      // by onIdle appears.
      for (final action in <SemanticsAction>[
        SemanticsAction.didGainAccessibilityFocus,
        SemanticsAction.didLoseAccessibilityFocus,
        SemanticsAction.focus,
        SemanticsAction.showOnScreen,
      ]) {
        sendSemanticsAction(tester, find.byType(ElevatedButton), action);
      }
      expect(log.events, <String>['idle']);

      sendSemanticsAction(
        tester,
        find.byType(ElevatedButton),
        SemanticsAction.tap,
      );
      expect(log.events, <String>['idle', 'active']);
      semantics.dispose();
    });

    testWidgets('focus moves reported by the platform keep the user active', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      for (var i = 0; i < 3; i++) {
        await tester.pump(almostIdle);
        await sendAccessibilityFocus(tester);
      }
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('focus moves reported by the platform do not end idle', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      await sendAccessibilityFocus(tester);
      expect(log.events, <String>['idle']);

      await tester.tap(find.text('content'));
      expect(log.events, <String>['idle', 'active']);
    });

    testWidgets('focus moves while the app is hidden are ignored', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(tick * 5);
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(tick * 4);
      // For example, the screen reader clearing its focus as the screen locks.
      sendSemanticsAction(
        tester,
        find.text('content'),
        SemanticsAction.didLoseAccessibilityFocus,
      );
      await sendAccessibilityFocus(tester);

      // The countdown wasn't restarted, so it ends on time.
      await tester.pump(tick);
      expect(log.events, <String>['idle']);
      comingToForeground.forEach(tester.binding.handleAppLifecycleStateChanged);
      semantics.dispose();
    });

    testWidgets('a focus move after a missed deadline still reports idle', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      final later = clock.now().add(const Duration(hours: 1));
      await withClock(Clock.fixed(later), () => sendAccessibilityFocus(tester));
      expect(log.events, <String>['idle']);
    });

    testWidgets('a throwing onActive does not swallow the action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var presses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onActive: () => throw StateError('boom'),
            child: Center(
              child: ElevatedButton(
                onPressed: () => presses++,
                child: const Text('button'),
              ),
            ),
          ),
        ),
      );

      await tester.pump(idleTime);
      sendSemanticsAction(
        tester,
        find.byType(ElevatedButton),
        SemanticsAction.tap,
      );
      expect(tester.takeException(), isStateError);
      expect(presses, 1);
      semantics.dispose();
    });

    testWidgets('a removed detector ignores screen reader events', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final log = CallbackLog();
      await pumpDetector(tester, log: log);
      await tester.pumpWidget(
        const MaterialApp(home: Center(child: Text('other'))),
      );

      sendSemanticsAction(
        tester,
        find.text('other'),
        SemanticsAction.didGainAccessibilityFocus,
      );
      await sendAccessibilityFocus(tester);
      await tester.pump(idleTime);
      expect(log.events, isEmpty);
      semantics.dispose();
    });
  });

  group('sleep and background', () {
    /// Moves the app through the lifecycle states of being backgrounded and
    /// brought back, while the system clock reads [timeAway] later than the
    /// test's clock, as if the device slept that long.
    void backgroundAndResume(WidgetTester tester, Duration timeAway) {
      const goingAway = <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ];
      const comingBack = <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ];
      goingAway.forEach(tester.binding.handleAppLifecycleStateChanged);
      final later = clock.now().add(timeAway);
      withClock(Clock.fixed(later), () {
        comingBack.forEach(tester.binding.handleAppLifecycleStateChanged);
      });
    }

    testWidgets('goes idle on resume if idleTime passed while asleep', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(tick);
      backgroundAndResume(tester, const Duration(hours: 1));
      expect(log.events, <String>['idle']);

      // The missed timer doesn't fire a second time.
      await tester.pump(idleTime * 2);
      expect(log.idle, 1);
    });

    testWidgets('counts a short sleep towards the countdown', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(tick * 2);
      // 2s awake + 5s asleep = 7s, so 3s are left.
      backgroundAndResume(tester, tick * 5);
      await tester.pump(tick * 2);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('the first interaction after a missed deadline reports idle '
        'first', (tester) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      final later = clock.now().add(const Duration(hours: 1));
      withClock(Clock.fixed(later), controller.reset);
      expect(log.events, <String>['idle', 'active']);
    });

    testWidgets('a detector built in the background waits for the foreground', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      // As when the system launches the app in the background, for example
      // for a background fetch.
      await pumpWhileHidden(
        tester,
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            onActive: log.onActive,
            controller: controller,
            child: const Text('content'),
          ),
        ),
      );
      expect(find.text('content'), findsOneWidget);

      await tester.pump(idleTime * 3);
      expect(log.events, isEmpty);
      // Activity reported from code doesn't start the countdown either.
      controller.reset();
      expect(log.events, isEmpty);

      <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(almostIdle);
      expect(log.events, isEmpty);

      await tester.pump(tick);
      expect(log.events, <String>['idle']);
    });

    testWidgets('reset while the app is hidden restarts the countdown', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      await tester.pump(tick * 5);
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      controller.reset();
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      comingToForeground.forEach(tester.binding.handleAppLifecycleStateChanged);
    });

    testWidgets('changing idleTime while the app is hidden restarts it', (
      tester,
    ) async {
      final log = CallbackLog();
      Widget build(Duration idleTime) {
        return MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: const SizedBox.expand(),
          ),
        );
      }

      await tester.pumpWidget(build(idleTime));
      await tester.pump(tick * 2);
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(tester, build(idleTime * 2));
      await tester.pump(idleTime * 2 - tick);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
      comingToForeground.forEach(tester.binding.handleAppLifecycleStateChanged);
    });

    testWidgets('an inactive but visible app counts down as usual', (
      tester,
    ) async {
      // For example, a desktop window without focus.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      expect(log.events, <String>['idle']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('a detector re-enabled while the app is hidden waits', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      Widget build({required bool enabled}) {
        return MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            enabled: enabled,
            onIdle: log.onIdle,
            controller: controller,
            child: const SizedBox.expand(),
          ),
        );
      }

      await tester.pumpWidget(build(enabled: false));
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(tester, build(enabled: true));
      await tester.pump(idleTime * 2);
      controller.reset();
      await tester.pump(idleTime * 2);
      expect(log.idle, 0);

      comingToForeground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a hidden app waits too, as on the web or desktop', (
      tester,
    ) async {
      // A hidden browser tab or a minimized window is hidden but not paused.
      final log = CallbackLog();
      <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(
        tester,
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(idleTime * 2);
      expect(log.idle, 0);

      <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(idleTime);
      expect(log.idle, 1);
    });

    testWidgets('a detached app counts as hidden', (tester) async {
      final log = CallbackLog();
      <AppLifecycleState>[
        ...goingToBackground,
        AppLifecycleState.detached,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(
        tester,
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(idleTime * 2);
      expect(log.idle, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(idleTime);
      expect(log.idle, 1);
    });

    testWidgets('a waiting detector starts when the app becomes inactive', (
      tester,
    ) async {
      // Inactive apps are visible, for example a desktop window without focus.
      final log = CallbackLog();
      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(
        tester,
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump(idleTime * 2);
      expect(log.idle, 0);

      <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(idleTime);
      expect(log.idle, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('changing idleTime before the app is visible still waits', (
      tester,
    ) async {
      final log = CallbackLog();
      Widget build(Duration idleTime) {
        return MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: const SizedBox.expand(),
          ),
        );
      }

      goingToBackground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await pumpWhileHidden(tester, build(idleTime));
      await pumpWhileHidden(tester, build(idleTime * 2));
      await tester.pump(idleTime * 3);
      expect(log.idle, 0);

      comingToForeground.forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(idleTime * 2 - tick);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('a running countdown can go idle in the background', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump(idleTime);
      expect(log.events, <String>['idle']);

      <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ].forEach(tester.binding.handleAppLifecycleStateChanged);
      await tester.pump();
      expect(log.events, <String>['idle']);
    });

    testWidgets('stops observing the app lifecycle when removed', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);
      await tester.pumpWidget(const SizedBox());

      backgroundAndResume(tester, const Duration(hours: 1));
      expect(log.events, isEmpty);
    });

    testWidgets('resuming while idle or disabled does nothing', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(idleTime);
      backgroundAndResume(tester, const Duration(hours: 1));
      expect(log.events, <String>['idle']);

      await pumpDetector(tester, log: log, enabled: false);
      backgroundAndResume(tester, const Duration(hours: 1));
      await tester.pump(idleTime * 2);
      expect(log.events, <String>['idle']);
    });

    testWidgets('a clock that goes backwards keeps the original deadline', (
      tester,
    ) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log);

      await tester.pump(tick * 8);
      backgroundAndResume(tester, const Duration(hours: -1));
      await tester.pump(tick);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });
  });

  group('back navigation', () {
    Future<void> sendBackGesture(WidgetTester tester, String method) {
      return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        SystemChannels.backGesture.codec.encodeMethodCall(
          MethodCall(method, <String, Object?>{
            'touchOffset': <double>[5, 300],
            'progress': 0.0,
            'swipeEdge': 0,
          }),
        ),
        (_) {},
      );
    }

    testWidgets('a predictive back gesture counts and still pops the route', (
      tester,
    ) async {
      final log = CallbackLog();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          builder: (context, child) => IdleDetector(
            idleTime: idleTime,
            onIdle: log.onIdle,
            child: child!,
          ),
          home: const Text('home'),
        ),
      );
      // A plain route, so no page transition claims the back gesture and the
      // app relies on the default handling, which the detector must not
      // block.
      unawaited(
        navigatorKey.currentState!.push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const Text('second'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      await tester.pump(almostIdle);
      await sendBackGesture(tester, 'startBackGesture');
      await sendBackGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
      expect(find.text('home'), findsOneWidget);

      // Well past the original deadline, but within idleTime of the gesture,
      // even counting the pop animation.
      await tester.pump(idleTime ~/ 2);
      expect(log.idle, 0);
    });
  });

  group('long idle times', () {
    testWidgets('never schedule a timer longer than the web supports', (
      tester,
    ) async {
      const maxDelay = Duration(milliseconds: 0x7FFFFFFF);
      final delays = <Duration>[];
      final log = CallbackLog();
      final recordTimers = ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          delays.add(duration);
          return parent.createTimer(zone, duration, callback);
        },
      );

      await runZoned(
        () =>
            pumpDetector(tester, log: log, idleTime: const Duration(days: 60)),
        zoneSpecification: recordTimers,
      );
      await tester.pump(const Duration(days: 60));
      expect(log.idle, 1);

      final detectorDelays = delays.where((d) => d > idleTime).toList();
      expect(detectorDelays, isNotEmpty);
      for (final delay in detectorDelays) {
        expect(delay, lessThanOrEqualTo(maxDelay));
      }
    });

    testWidgets('work beyond the longest single timer delay', (tester) async {
      final log = CallbackLog();
      await pumpDetector(tester, log: log, idleTime: const Duration(days: 60));

      await tester.pump(const Duration(days: 59));
      expect(log.idle, 0);

      await tester.pump(const Duration(days: 1));
      expect(log.idle, 1);
    });
  });

  group('IdleDetectorController', () {
    testWidgets('is detached until used by a detector', (tester) async {
      final controller = IdleDetectorController();
      expect(controller.isAttached, isFalse);
      expect(controller.isIdle, isFalse);
      controller.reset(); // No-op, must not throw.

      final log = CallbackLog();
      await pumpDetector(tester, log: log, controller: controller);
      expect(controller.isAttached, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(controller.isAttached, isFalse);
    });

    testWidgets('isIdle follows the idle state', (tester) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      expect(controller.isIdle, isFalse);
      await tester.pump(idleTime);
      expect(controller.isIdle, isTrue);

      await tester.tap(find.text('content'));
      expect(controller.isIdle, isFalse);
    });

    testWidgets('reset restarts the countdown', (tester) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      await tester.pump(almostIdle);
      controller.reset();
      await tester.pump(almostIdle);
      expect(log.idle, 0);

      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('reset while idle calls onActive', (tester) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: controller);

      await tester.pump(idleTime);
      controller.reset();
      expect(log.events, <String>['idle', 'active']);
      expect(controller.isIdle, isFalse);
    });

    testWidgets('reset does nothing while disabled', (tester) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      await pumpDetector(
        tester,
        log: log,
        controller: controller,
        enabled: false,
      );

      controller.reset();
      await tester.pump(idleTime * 2);
      expect(log.events, isEmpty);
    });

    testWidgets('can be swapped for another controller', (tester) async {
      final log = CallbackLog();
      final first = IdleDetectorController();
      final second = IdleDetectorController();
      await pumpDetector(tester, log: log, controller: first);
      await pumpDetector(tester, log: log, controller: second);

      expect(first.isAttached, isFalse);
      expect(second.isAttached, isTrue);

      await tester.pump(almostIdle);
      first.reset();
      await tester.pump(tick);
      expect(log.idle, 1);
    });

    testWidgets('survives the detector being replaced by a new one', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      Widget build(Key key) {
        return MaterialApp(
          home: IdleDetector(
            key: key,
            idleTime: idleTime,
            onIdle: log.onIdle,
            controller: controller,
            child: const SizedBox.expand(),
          ),
        );
      }

      await tester.pumpWidget(build(const ValueKey(1)));
      // A new key creates a new detector before the old one is disposed.
      await tester.pumpWidget(build(const ValueKey(2)));
      expect(controller.isAttached, isTrue);

      await tester.pump(almostIdle);
      controller.reset();
      await tester.pump(almostIdle);
      expect(log.idle, 0);
    });

    testWidgets('reset applies to every detector using it', (tester) async {
      final outer = CallbackLog();
      final inner = CallbackLog();
      final controller = IdleDetectorController();
      Widget build({required bool withInner}) {
        return MaterialApp(
          home: IdleDetector(
            idleTime: idleTime,
            onIdle: outer.onIdle,
            controller: controller,
            child: withInner
                ? IdleDetector(
                    idleTime: idleTime,
                    onIdle: inner.onIdle,
                    controller: controller,
                    child: const SizedBox.expand(),
                  )
                : const SizedBox.expand(),
          ),
        );
      }

      await tester.pumpWidget(build(withInner: true));
      await tester.pump(almostIdle);
      controller.reset();
      await tester.pump(almostIdle);
      expect(outer.idle, 0);
      expect(inner.idle, 0);

      // Removing one detector leaves the controller working for the other.
      await tester.pumpWidget(build(withInner: false));
      expect(controller.isAttached, isTrue);
      expect(controller.isIdle, isFalse);
      controller.reset();
      await tester.pump(almostIdle);
      expect(outer.idle, 0);
      await tester.pump(tick);
      expect(outer.idle, 1);
    });

    testWidgets('isIdle reports the detector that attached most recently', (
      tester,
    ) async {
      final controller = IdleDetectorController();
      await tester.pumpWidget(
        MaterialApp(
          home: IdleDetector(
            idleTime: idleTime * 2,
            controller: controller,
            child: IdleDetector(
              idleTime: idleTime,
              controller: controller,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // The inner detector is created after the outer one.
      await tester.pump(idleTime);
      expect(controller.isIdle, isTrue);
    });

    testWidgets('isIdle can be read while a keyed detector is replaced', (
      tester,
    ) async {
      final controller = IdleDetectorController();
      final observed = <bool>[];
      Widget build(Key key) {
        return MaterialApp(
          home: IdleDetector(
            key: key,
            idleTime: idleTime,
            controller: controller,
            child: Builder(
              builder: (context) {
                observed.add(controller.isIdle);
                return const SizedBox.expand();
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(build(const ValueKey(1)));
      await tester.pump(idleTime);
      await tester.pumpWidget(build(const ValueKey(2)));
      expect(tester.takeException(), isNull);
      // The new detector starts active, even though the old one was idle.
      expect(observed, <bool>[false, false]);
    });

    testWidgets('stays attached when the detector moves in the tree', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      final detectorKey = GlobalKey();
      Widget detector() => IdleDetector(
        key: detectorKey,
        idleTime: idleTime,
        onIdle: log.onIdle,
        controller: controller,
        child: const SizedBox.expand(),
      );

      await tester.pumpWidget(MaterialApp(home: detector()));
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: SizedBox(child: detector())),
        ),
      );
      expect(controller.isAttached, isTrue);

      await tester.pump(almostIdle);
      controller.reset();
      await tester.pump(almostIdle);
      expect(log.idle, 0);
    });

    testWidgets('stays attached when a keyed detector in a list is replaced', (
      tester,
    ) async {
      final log = CallbackLog();
      final controller = IdleDetectorController();
      Widget build(Key key) {
        return MaterialApp(
          home: Column(
            children: [
              Expanded(
                key: key,
                child: IdleDetector(
                  idleTime: idleTime,
                  onIdle: log.onIdle,
                  controller: controller,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      }

      await tester.pumpWidget(build(const ValueKey(1)));
      await tester.pumpWidget(build(const ValueKey(2)));
      expect(controller.isAttached, isTrue);
      expect(controller.isIdle, isFalse);

      await tester.pump(almostIdle);
      controller.reset();
      await tester.pump(almostIdle);
      expect(log.idle, 0);
    });
  });
}
