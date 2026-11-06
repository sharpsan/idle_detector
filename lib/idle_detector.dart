/// Detects when the user stops interacting with a Flutter app.
///
/// Wrap your app (or any part of it) in an [IdleDetector]. It calls
/// [IdleDetector.onIdle] after a period with no touch, mouse, trackpad,
/// keyboard or screen reader activity, and [IdleDetector.onActive] when the
/// user comes back.
///
/// ```dart
/// IdleDetector(
///   idleTime: const Duration(minutes: 5),
///   onIdle: () => print('The user went idle.'),
///   onActive: () => print('The user is back.'),
///   child: const MyApp(),
/// )
/// ```
///
/// Use an [IdleDetectorController] to report activity that the widget can't
/// see itself, or to check whether the user is currently idle.
library;

// Imported as well as exported so the links in the library comment resolve.
import 'src/idle_detector.dart';

export 'src/idle_detector.dart';
