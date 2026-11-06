## 1.0.0

First stable release.

### Breaking changes

- `onIdle` is now a `VoidCallback?` instead of `Function?`.
- `idleTime` must be greater than `Duration.zero`. This is checked with an
  assertion in debug mode.
- Requires Dart 3.8 and Flutter 3.32 or newer.

More kinds of input now count as activity, and time in the background now
counts as inactivity, which changes when `onIdle` fires. See "Migrating from
0.9.x" in the README.

### New

- `onActive` callback, called on the first interaction after going idle.
- `IdleDetectorController` to report activity from code (`reset()`) and read
  the current state (`isIdle`, `isAttached`).
- `enabled` parameter to pause and resume detection. The child keeps its state
  when it changes.
- Mouse movement, right and middle mouse clicks, mouse-wheel scrolling,
  hardware keyboard input, screen reader actions (TalkBack, VoiceOver and
  others) and Android predictive back gestures now count as activity. Use
  `detectKeyboardActivity: false` to ignore the keyboard. Moving a screen
  reader's focus keeps the user active but doesn't end an idle period,
  because screen readers also move focus by themselves.
- Time in the background and while the device sleeps now counts as
  inactivity. If `idleTime` passed in the meantime, `onIdle` is called when
  the app resumes, or before `onActive` on the next interaction. Previously
  the countdown relied on a timer alone, and timers can pause while a device
  sleeps. A detector created or re-enabled while the app reports that it's
  hidden, paused or detached, for example during a background fetch, starts
  its countdown when the app becomes visible.

### Fixes

- Pointer and trackpad movement during a drag or scroll now keeps the user
  active. Previously only the start of a drag counted (and its end, outside
  scroll views), so the user could go idle in the middle of a long drag or
  scroll.
- The detector uses a `Listener` instead of a `GestureDetector`, so it no
  longer adds gesture recognizers to the arena. It no longer takes taps or
  drags away from gesture handlers around it, such as an `InkWell`, a
  `ListTile` or a `PageView` whose pages are wrapped in a detector, or blocks
  taps to widgets behind it in a `Stack`. It also no longer adds tap and
  scroll semantics actions to the area it wraps.
- Changing `idleTime` while the user is active now restarts the countdown with
  the new duration right away.
- An `idleTime` longer than about 24 days no longer fires almost immediately
  on the web.

### Other

- Errors thrown synchronously by `onIdle` and `onActive` are reported to
  `FlutterError.onError`. Previously, an error thrown by `onIdle` escaped as
  an uncaught error in the current zone. Errors from `async` callbacks still
  go to the zone.
- Documented the whole public API, and rewrote the README.
- Added an example app and a test suite.
- Added a dependency on `clock`, used to measure time across device sleep.
- Updated to `flutter_lints` 6.

## 0.9.0

Initial release
