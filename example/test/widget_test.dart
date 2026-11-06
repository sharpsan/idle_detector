import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_detector_example/main.dart';

void main() {
  testWidgets('shows the overlay when idle and hides it on interaction', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    expect(find.text('Still there?'), findsNothing);

    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    await tester.tapAt(const Offset(10, 300));
    await tester.pump();
    expect(find.text('Still there?'), findsNothing);
    expect(find.textContaining('Became active'), findsOneWidget);
  });

  testWidgets('typing keeps the user active', (tester) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());

    await tester.pump(kIdleTime - const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump(kIdleTime - const Duration(seconds: 1));
    expect(find.text('Still there?'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Still there?'), findsOneWidget);
  });

  testWidgets('never goes idle while detection is disabled', (tester) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(kIdleTime * 3);
    expect(find.text('Still there?'), findsNothing);
  });

  testWidgets('the key that dismisses the overlay does not reach the app', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());

    // Give the "Open a dialog" button keyboard focus, as if tabbed to.
    Focus.of(tester.element(find.text('Open a dialog'))).requestFocus();
    await tester.pump();

    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Still there?'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a screen reader user can dismiss the overlay', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const IdleDetectorExampleApp());

    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    tester.semantics.tap(find.semantics.byLabel(RegExp('Tap anywhere')));
    await tester.pump();
    expect(find.text('Still there?'), findsNothing);
    semantics.dispose();
  });

  testWidgets('system keys still reach the platform', (tester) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    // Keys the overlay doesn't use, such as the volume keys, are reported as
    // unhandled, so the platform still acts on them.
    expect(
      await tester.sendKeyDownEvent(LogicalKeyboardKey.audioVolumeUp),
      isFalse,
    );
    expect(
      await tester.sendKeyUpEvent(LogicalKeyboardKey.audioVolumeUp),
      isFalse,
    );

    await tester.pump();
    expect(find.text('Still there?'), findsNothing);
  });

  testWidgets('Back dismisses the overlay and still reaches the app', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    await tester.tap(find.text('Open a dialog'));
    await tester.pumpAndSettle();
    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    // The simulator only maps the Back key for the web, but the framework
    // handles it the same way everywhere.
    Future<bool> sendBack(bool down) {
      return down
          ? tester.sendKeyDownEvent(
              LogicalKeyboardKey.goBack,
              physicalKey: PhysicalKeyboardKey.browserBack,
              platform: 'web',
            )
          : tester.sendKeyUpEvent(
              LogicalKeyboardKey.goBack,
              physicalKey: PhysicalKeyboardKey.browserBack,
              platform: 'web',
            );
    }

    expect(await sendBack(true), isFalse);
    expect(await sendBack(false), isFalse);
    await tester.pump();
    expect(find.text('Still there?'), findsNothing);

    // Android turns an unhandled Back key into back navigation.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Tab on the overlay does not move focus behind it', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    await tester.pump(kIdleTime);
    final overlayFocus = Focus.of(tester.element(find.text('Still there?')));
    expect(overlayFocus.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    // The overlay goes away on the next frame. Until then, focus stays on it.
    expect(find.text('Still there?'), findsOneWidget);
    expect(overlayFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('dismissing the overlay gives keyboard focus back', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    final buttonFocus = Focus.of(tester.element(find.text('Open a dialog')));
    buttonFocus.requestFocus();
    await tester.pump();

    await tester.pump(kIdleTime);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.text('Still there?'), findsNothing);
    expect(buttonFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('the overlay is the only thing screen readers see', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const IdleDetectorExampleApp());
    expect(find.semantics.byLabel('Open a dialog'), findsOneWidget);

    await tester.pump(kIdleTime);
    expect(find.semantics.byLabel('Open a dialog'), findsNothing);
    // The overlay is presented as its own screen, named "Still there?".
    for (final flag in <SemanticsFlag>[
      SemanticsFlag.scopesRoute,
      SemanticsFlag.namesRoute,
    ]) {
      final labels = find.semantics
          .byFlag(flag)
          .evaluate()
          .map((node) => node.label);
      expect(labels, <String>['Still there?'], reason: '$flag');
    }
    semantics.dispose();
  });

  testWidgets('the tap that dismisses the overlay does not reach the app', (
    tester,
  ) async {
    await tester.pumpWidget(const IdleDetectorExampleApp());
    final button = tester.getCenter(find.text('Open a dialog'));
    await tester.pump(kIdleTime);
    expect(find.text('Still there?'), findsOneWidget);

    await tester.tapAt(button);
    await tester.pumpAndSettle();
    expect(find.text('Still there?'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
