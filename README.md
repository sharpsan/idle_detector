# idle_detector

[![pub package](https://img.shields.io/pub/v/idle_detector.svg)](https://pub.dev/packages/idle_detector)
[![CI](https://github.com/sharpsan/idle_detector/actions/workflows/ci.yml/badge.svg)](https://github.com/sharpsan/idle_detector/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/sharpsan/idle_detector/blob/main/LICENSE)

A Flutter widget that tells you when the user stops interacting with your app,
and when they come back.

Use it to log out or lock the app after a period of inactivity, show an
"Are you still there?" prompt or a screensaver, or pause work while nobody is
watching.

## Features

- Calls `onIdle` after a period with no interaction, and `onActive` when the
  user returns.
- Detects taps, drags, scrolling, mouse movement, the mouse wheel, trackpad
  gestures, hardware keyboard input and screen reader actions.
- Counts time while the app is in the background or the device is asleep, so
  a timeout that expired while the phone was locked fires as soon as the app
  is back in the foreground.
- Stays out of the way. It listens to raw pointer events instead of joining
  the gesture arena, so buttons, scroll views and other gestures work as
  before. It never consumes key events.
- Report activity from code, and check whether the user is idle, with an
  `IdleDetectorController`.
- Pause detection with `enabled: false`.
- Supports Android, iOS, web, Windows, macOS and Linux.

## Getting started

```sh
flutter pub add idle_detector
```

```dart
import 'package:idle_detector/idle_detector.dart';
```

## Usage

Wrap a widget in `IdleDetector`, set how long the user must be inactive, and
handle the callbacks:

```dart
IdleDetector(
  idleTime: const Duration(minutes: 5),
  onIdle: () => print('No interaction for 5 minutes.'),
  onActive: () => print('The user is back.'),
  child: const HomePage(),
)
```

`onIdle` is called once per idle period. The detector then stays idle until
the next interaction, which calls `onActive` and starts a new countdown.

### Watch the whole app

Only pointer events inside the area the detector's `child` covers count.
Dialogs, menus and bottom sheets are shown above the page by the `Navigator`,
so wrapping a single page misses them. To cover everything, wrap the navigator
with the `builder` parameter of `MaterialApp` (`CupertinoApp` and `WidgetsApp`
have one too), as shown below. Wrapping the whole `MaterialApp` works as well.

The `builder` context sits above the navigator, so use a `navigatorKey` to
navigate from the callbacks:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

MaterialApp(
  navigatorKey: navigatorKey,
  builder: (context, child) => IdleDetector(
    idleTime: const Duration(minutes: 10),
    onIdle: () {
      // For example, sign the user out and return to the login screen.
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    },
    child: child!,
  ),
  // routes, home, ...
)
```

### Show something while the user is idle

Keep the idle state in a `StatefulWidget` and use `onActive` to undo whatever
`onIdle` did:

```dart
class _MyAppState extends State<MyApp> {
  bool _isIdle = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => IdleDetector(
        idleTime: const Duration(minutes: 2),
        onIdle: () => setState(() => _isIdle = true),
        onActive: () => setState(() => _isIdle = false),
        child: Stack(
          children: [
            child!,
            // Inside the detector, so tapping the screensaver dismisses it.
            if (_isIdle) const Screensaver(),
          ],
        ),
      ),
      home: const HomePage(),
    );
  }
}
```

The detector never consumes key events, so the key press that wakes the app
also reaches whatever widget has focus. To stop that, have the screensaver take
keyboard focus, in a `FocusScope` of its own so that Tab can't move focus
behind it, as the
[example app](https://github.com/sharpsan/idle_detector/blob/main/example/lib/main.dart)
does. Keys it doesn't handle, such as Back and the volume keys, still reach the
platform.

### Report activity from code

Some activity never reaches the detector as a pointer or key event. On-screen
keyboards, for example, usually send text without key events, and on the web,
platform views such as maps receive their own input. Report this activity with
an `IdleDetectorController`:

```dart
final idleController = IdleDetectorController();

IdleDetector(
  idleTime: const Duration(minutes: 5),
  controller: idleController,
  onIdle: _lockApp,
  child: Column(
    children: [
      TextField(
        // Count typing on a phone's on-screen keyboard as activity.
        onChanged: (_) => idleController.reset(),
      ),
      // ...
    ],
  ),
)
```

`reset()` behaves like a real interaction: it restarts the countdown and, if
the user was idle, calls `onActive`. The controller also has `isIdle`, to check
the current state, and `isAttached`, to check whether a detector is using it.

A controller is meant for one `IdleDetector` at a time. If several detectors
use it at once, `reset()` applies to all of them, and `isIdle` reports the one
that started using the controller most recently.

### Pause detection

Set `enabled` to `false` to stop the countdown. For example, turn detection on
only while the user is signed in, or off while a video plays:

```dart
IdleDetector(
  idleTime: const Duration(minutes: 15),
  enabled: isSignedIn && !isVideoPlaying,
  onIdle: signOut,
  child: child,
)
```

While disabled, nothing is tracked and neither callback is called. If the user
was idle, the idle state is cleared without calling `onActive`. Re-enabling
starts a fresh countdown. The child keeps its state when `enabled` changes.

### Background and device sleep

Time that passes while the app is in the background, or while the device is
asleep, counts as inactivity. If the platform keeps the app running in the
background, `onIdle` can be called there. Timers can pause while a device
sleeps, so the detector also checks the system clock:

- when the app returns to the foreground, `onIdle` is called right away if
  `idleTime` has passed since the last activity;
- if the app stayed in the foreground, for example on a computer that went to
  sleep, the first interaction after the gap calls `onIdle` first and then
  `onActive`.

Because this check uses the system clock, changing the device's clock can make
the detector go idle early or late.

A detector that is created, or re-enabled, while the app reports that it's
hidden, paused or detached doesn't start its countdown until the app becomes
visible.
For example, if the system launched the app in the background for a background
fetch, time before the user has seen the app doesn't count. Whether a
background launch is reported as hidden depends on the platform. Before the
platform reports any lifecycle state, the app counts as visible, so in
add-to-app setups that start a Flutter engine before showing a Flutter screen,
create or enable the detector once that screen is shown. A countdown that is
already running keeps running in the background.

## What counts as activity

| Activity | Counts when |
| --- | --- |
| Touch, pen and mouse presses, drags and scrolls | A pointer goes down over `child`. Its moves and release then count wherever they happen. |
| Mouse movement (hover) | The mouse moves over `child`. |
| Mouse wheel | The wheel turns while the mouse is over `child`. |
| Trackpad scroll or zoom | The gesture starts over `child`. |
| Hardware keyboard | Any key event anywhere in the app, if `detectKeyboardActivity` is `true` (the default). |
| Screen readers (TalkBack, VoiceOver and others) | Any action, such as activating a button, scrolling or moving focus, anywhere in the app. Moving focus alone doesn't end an idle period (see below). |
| Android predictive back gesture | The gesture starts, anywhere in the app, if predictive back is enabled for the app and there's a route to go back to. On Flutter 3.32, a detector created after the page that handles the gesture, such as one below the app's navigator, can miss it when a page transition such as `PredictiveBackPageTransitionsBuilder` handles it. Create the detector up front in `MaterialApp.builder` to be sure. |
| `IdleDetectorController.reset()` | It's called. |

Things that do **not** count as activity:

- pointers that go down outside `child`;
- typing on most on-screen keyboards (use the controller, as shown above);
- on the web, input to platform views such as an `HtmlElementView` showing a
  map or video player;
- system back presses, unless the platform reports them as a key event or a
  predictive back gesture;
- anything that isn't user input, such as animations, video playback or
  network activity.

### Screen readers

Moving a screen reader's focus keeps an active user active, so someone reading
by swiping from item to item isn't treated as idle. It doesn't end an idle
period, though: screen readers also move their focus by themselves when the
screen changes, for example to the UI that `onIdle` shows. Other screen reader
actions, such as activating a button or scrolling, do end it.

So make sure anything you show while the user is idle has something a screen
reader user can activate. The
[example app](https://github.com/sharpsan/idle_detector/blob/main/example/lib/main.dart)
makes its whole overlay a button.

Focus moves also restart the countdown of every detector that isn't idle yet.
If a screen reader moves its focus to UI that one detector shows, such as a
"you'll be signed out soon" warning, another detector's countdown, such as the
sign-out itself, starts over.

## API

| `IdleDetector` parameter | Description |
| --- | --- |
| `idleTime` | Required. How long the user must be inactive before `onIdle` is called. Must be greater than zero. If it changes while the user is active, the countdown restarts with the new duration. |
| `onIdle` | Called once when the user has been inactive for `idleTime`. |
| `onActive` | Called on the first interaction after the user went idle, whether or not `onIdle` is set. |
| `controller` | An `IdleDetectorController` for reporting activity from code and reading `isIdle`. |
| `enabled` | Whether detection is running. Defaults to `true`. |
| `detectKeyboardActivity` | Whether hardware key events count as activity. Defaults to `true`. |
| `child` | Required. The widget whose pointer events are watched. |

Errors thrown synchronously by `onIdle` and `onActive` are reported to
`FlutterError.onError` instead of interrupting the event that triggered them.
Errors from `async` callbacks go to the current zone, as for any other
callback.

See the [API reference](https://pub.dev/documentation/idle_detector/latest/)
for details.

## Migrating from 0.9.x

- `onIdle` is now a `VoidCallback?` instead of `Function?`. Callbacks written
  as `() { ... }` don't need to change.
- `idleTime` must be greater than `Duration.zero`. A zero or negative value
  fails an assertion in debug mode.
- Dart 3.8 and Flutter 3.32 or newer are required.
- More input counts as activity: mouse movement, right and middle mouse
  clicks, the mouse wheel, hardware keys, screen reader actions, Android
  predictive back gestures, and pointer movement during long drags and
  scrolls. To ignore the keyboard, set `detectKeyboardActivity: false`.
- Time in the background and while the device sleeps now counts as
  inactivity, so `onIdle` may be called when the app resumes.
- The detector no longer takes taps or drags away from gesture handlers
  around it, such as an `InkWell`, a `ListTile` or a `PageView`, or blocks
  taps to widgets behind it in a `Stack`.

## Example

The [example app](https://github.com/sharpsan/idle_detector/tree/main/example)
shows a "Still there?" screen after 5 seconds of inactivity. It also shows how
to report typing with a controller and turn detection on and off.

The example folder holds only the Dart code. To run it, generate the platform
folders once (git ignores them):

```sh
cd example
flutter create .
flutter run
```

## Contributing

Bug reports are welcome on the
[issue tracker](https://github.com/sharpsan/idle_detector/issues), and pull
requests on [GitHub](https://github.com/sharpsan/idle_detector/pulls).

To run the checks locally:

```sh
flutter pub get
dart format --set-exit-if-changed .
flutter analyze
flutter test
cd example && flutter test
```

## License

[MIT](https://github.com/sharpsan/idle_detector/blob/main/LICENSE)
