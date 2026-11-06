import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Calls [onIdle] when the user hasn't interacted with [child] for
/// [idleTime], and [onActive] when they interact again.
///
/// Activity includes:
///
/// * pointer events inside this widget: touches, mouse clicks, mouse movement
///   (hover), drags, mouse-wheel scrolling and trackpad gestures;
/// * key presses on a hardware keyboard, anywhere in the app (unless
///   [detectKeyboardActivity] is `false`);
/// * actions from screen readers such as TalkBack and VoiceOver, anywhere in
///   the app (see below for focus moves);
/// * the start of an Android predictive back gesture, anywhere in the app,
///   when there's a route to go back to (on Flutter 3.32, a detector created
///   after the page that handles the
///   gesture, such as one below the app's navigator, can miss it when a page
///   transition such as `PredictiveBackPageTransitionsBuilder` handles it);
/// * calls to [IdleDetectorController.reset].
///
/// Input that never reaches Flutter as one of these events isn't detected.
/// That includes typing on most on-screen keyboards; on the web, input to
/// platform views such as an `HtmlElementView`; and back navigation that the
/// platform reports only as a route pop, such as the browser's back button.
/// Report such activity with [IdleDetectorController.reset].
///
/// [IdleDetector] uses a [Listener], so it never joins the gesture arena. It
/// does not block, delay or steal taps, drags or scrolls from widgets inside
/// it or behind it, and it never marks key events as handled.
///
/// [onIdle] fires once per idle period. After that, the detector stays idle
/// until the next interaction, which fires [onActive] and starts a new
/// countdown.
///
/// Moving a screen reader's focus keeps an active user active, so someone
/// reading by swiping from item to item isn't treated as idle. It doesn't end
/// an idle period, though: screen readers also move their focus by themselves
/// when the screen changes, for example to the UI that [onIdle] shows. Other
/// screen reader actions, such as activating a button or scrolling, do end it.
/// Make sure any UI shown while idle has something a screen reader user can
/// activate.
///
/// Time that passes while the device is asleep or the app is in the
/// background counts as inactivity, and [onIdle] can be called while the app
/// is in the background. When the app resumes, or on the first interaction
/// after a long gap, [onIdle] is called if [idleTime] has passed in the
/// meantime. This check uses the system clock, so changing the device's clock
/// can make the detector go idle early or late.
///
/// A detector that is created, or re-enabled, while the app reports that it's
/// hidden, paused or detached doesn't start its countdown until the app
/// becomes visible, for example when the system launched the app in the
/// background.
/// Whether a background launch is reported as hidden depends on the platform.
/// Before the platform reports any lifecycle state, the app counts as visible.
/// In add-to-app setups that start a Flutter engine before showing a Flutter
/// screen, create or enable the detector once that screen is shown.
///
/// Wrap the app's navigator through the `builder` parameter of `MaterialApp`,
/// `CupertinoApp` or [WidgetsApp]. Interactions with every route, dialog and
/// bottom sheet then count as activity:
///
/// ```dart
/// MaterialApp(
///   builder: (context, child) => IdleDetector(
///     idleTime: const Duration(minutes: 5),
///     onIdle: () => print('Idle for 5 minutes'),
///     child: child!,
///   ),
///   home: const HomePage(),
/// )
/// ```
///
/// See also:
///
///  * [IdleDetectorController], which reports activity from code and reads
///    the current idle state.
class IdleDetector extends StatefulWidget {
  /// Creates a widget that watches [child] for user activity.
  ///
  /// [idleTime] must be greater than [Duration.zero].
  const IdleDetector({
    super.key,
    required this.idleTime,
    this.onIdle,
    this.onActive,
    this.controller,
    this.enabled = true,
    this.detectKeyboardActivity = true,
    required this.child,
  });

  /// How long the user must be inactive before [onIdle] is called.
  ///
  /// If this changes while the user is active, the countdown restarts from
  /// zero with the new duration. If it changes while the user is idle, the new
  /// duration applies from the next interaction.
  final Duration idleTime;

  /// Called once when the user has been inactive for [idleTime].
  ///
  /// It is not called again until the user interacts and then goes idle
  /// again, or until [enabled] is turned off and on again.
  final VoidCallback? onIdle;

  /// Called on the first interaction after the user went idle, that is,
  /// after [onIdle] was called, or would have been if it were set.
  ///
  /// It is not called for interactions while the user is already active, or
  /// when a screen reader only moves its focus.
  final VoidCallback? onActive;

  /// An optional controller for reporting activity from code and reading the
  /// current idle state.
  final IdleDetectorController? controller;

  /// Whether the detector is running.
  ///
  /// When `false`, the countdown is stopped, no activity is tracked, and
  /// neither [onIdle] nor [onActive] is called. If the user was idle, the idle
  /// state is cleared without calling [onActive].
  ///
  /// When this changes back to `true`, a new countdown of [idleTime] starts.
  ///
  /// Defaults to `true`.
  final bool enabled;

  /// Whether hardware keyboard events count as activity.
  ///
  /// Keyboard events are detected app-wide, wherever focus is, not only
  /// inside [child].
  ///
  /// On-screen (soft) keyboards usually send text without key events, so
  /// typing on them does not count. Call [IdleDetectorController.reset] from
  /// the text field's `onChanged` to count it.
  ///
  /// On Android, the Back button often arrives as a key event too, so turning
  /// this off can stop Back presses from counting.
  ///
  /// Defaults to `true`.
  final bool detectKeyboardActivity;

  /// The widget below this widget in the tree.
  ///
  /// Only pointers that go down, hover or scroll inside the area this widget
  /// covers count as activity. Once a pointer has gone down inside, its moves
  /// and release count wherever they happen.
  final Widget child;

  @override
  State<IdleDetector> createState() => _IdleDetectorState();
}

class _IdleDetectorState extends State<IdleDetector>
    with WidgetsBindingObserver {
  /// The longest delay that a [Timer] supports on every platform. On the web,
  /// longer delays overflow and fire almost immediately.
  static const Duration _maxTimerDelay = Duration(milliseconds: 0x7FFFFFFF);

  Timer? _timer;
  bool _isIdle = false;
  bool _listeningToKeyboard = false;

  /// Whether a countdown should have started while the app was hidden or
  /// paused, and will start when the app becomes visible instead.
  bool _waitingForForeground = false;

  /// When the current countdown started, by the system clock.
  ///
  /// Timers don't advance while the device sleeps, so this is used to catch up
  /// on time that the timer missed.
  DateTime _countdownStart = clock.now();

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addObserver(this);
    SemanticsBinding.instance.addSemanticsActionListener(
      _handleSemanticsAction,
    );
    ServicesBinding.instance.accessibilityFocus.addListener(
      _handleAccessibilityFocus,
    );
    _updateKeyboardListener();
    if (widget.enabled) {
      _startFreshCountdown();
    }
  }

  @override
  void didUpdateWidget(IdleDetector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }

    _updateKeyboardListener();

    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _startFreshCountdown();
      } else {
        _stopTimer();
        _isIdle = false;
      }
    } else if (widget.enabled &&
        !_isIdle &&
        !_waitingForForeground &&
        widget.idleTime != oldWidget.idleTime) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _stopTimer();
    if (_listeningToKeyboard) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
      _listeningToKeyboard = false;
    }
    SemanticsBinding.instance.removeSemanticsActionListener(
      _handleSemanticsAction,
    );
    ServicesBinding.instance.accessibilityFocus.removeListener(
      _handleAccessibilityFocus,
    );
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?._detach(this);
    super.dispose();
  }

  void _updateKeyboardListener() {
    final shouldListen = widget.enabled && widget.detectKeyboardActivity;
    if (shouldListen == _listeningToKeyboard) {
      return;
    }
    if (shouldListen) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    } else {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    _listeningToKeyboard = shouldListen;
  }

  /// Starts a countdown when detection starts, from [initState] or when
  /// [IdleDetector.enabled] becomes `true`.
  ///
  /// If the app is hidden, paused or detached, waits until it becomes visible
  /// instead:
  /// time before the user has seen the app doesn't count. A countdown that is
  /// already running keeps running in the background.
  void _startFreshCountdown() {
    if (_isAppHidden(WidgetsBinding.instance.lifecycleState)) {
      _stopTimer();
      _waitingForForeground = true;
    } else {
      _startTimer();
    }
  }

  /// Starts a full countdown of [IdleDetector.idleTime] from now.
  void _startTimer() {
    _waitingForForeground = false;
    _countdownStart = clock.now();
    _scheduleTimeout(widget.idleTime);
  }

  static bool _isAppHidden(AppLifecycleState? state) {
    return switch (state) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached => true,
      AppLifecycleState.resumed || AppLifecycleState.inactive || null => false,
    };
  }

  /// Calls [_handleTimeout] after [delay], in steps no longer than
  /// [_maxTimerDelay].
  void _scheduleTimeout(Duration delay) {
    _timer?.cancel();
    if (delay > _maxTimerDelay) {
      _timer = Timer(
        _maxTimerDelay,
        () => _scheduleTimeout(delay - _maxTimerDelay),
      );
    } else {
      _timer = Timer(delay, _handleTimeout);
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _waitingForForeground = false;
  }

  /// How long the current countdown has run by the system clock, or `null` if
  /// the system clock went backwards since it started.
  ///
  /// When this is `null`, the clock can't be trusted, and the timer's own
  /// deadline is kept.
  Duration? get _elapsedByClock {
    final elapsed = clock.now().difference(_countdownStart);
    return elapsed.isNegative ? null : elapsed;
  }

  void _handleTimeout() {
    _timer = null;
    _isIdle = true;
    _invokeCallback(widget.onIdle, 'onIdle');
  }

  /// Calls a user callback, reporting any synchronous error to
  /// [FlutterError.reportError] instead of throwing it.
  ///
  /// Many callers run inside framework dispatch loops (semantics actions, app
  /// lifecycle, back navigation) that would skip the remaining listeners, or
  /// the action itself, if a listener threw.
  void _invokeCallback(VoidCallback? callback, String name) {
    if (callback == null) {
      return;
    }
    try {
      callback();
    } catch (exception, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'idle_detector',
          context: ErrorDescription('while calling IdleDetector.$name'),
        ),
      );
    }
  }

  /// Handles user activity.
  ///
  /// If [canEndIdle] is `false`, the activity keeps an active user active but
  /// doesn't end an idle period.
  void _handleActivity({bool canEndIdle = true}) {
    if (!mounted) {
      // A pointer that went down on this detector keeps sending its moves and
      // release here even after the detector has left the tree.
      return;
    }
    if (!widget.enabled || _waitingForForeground) {
      // While waiting for the app to become visible, there's no countdown to
      // restart. It starts when the app becomes visible.
      return;
    }
    if (!canEndIdle && _isAppHidden(WidgetsBinding.instance.lifecycleState)) {
      // Screen readers can move or clear their focus while the app is hidden,
      // for example when the screen locks. That isn't the user.
      return;
    }
    final elapsed = _elapsedByClock;
    if (!_isIdle && elapsed != null && elapsed >= widget.idleTime) {
      // The timer missed the deadline, for example because the device was
      // asleep. The user was idle, so report it before this activity.
      _stopTimer();
      _handleTimeout();
    }
    if (_isIdle && !canEndIdle) {
      return;
    }
    final wasIdle = _isIdle;
    _isIdle = false;
    _startTimer();
    if (wasIdle) {
      _invokeCallback(widget.onActive, 'onActive');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) {
      return;
    }
    if (_waitingForForeground) {
      if (!_isAppHidden(state)) {
        _startTimer();
      }
      return;
    }
    if (state != AppLifecycleState.resumed || _isIdle) {
      return;
    }
    // Catch up on time that passed while the app was paused or the device was
    // asleep.
    final elapsed = _elapsedByClock;
    if (elapsed == null) {
      return;
    }
    if (elapsed >= widget.idleTime) {
      _stopTimer();
      _handleTimeout();
    } else {
      _scheduleTimeout(widget.idleTime - elapsed);
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _handleActivity();
    // Let the app handle the back gesture as usual.
    return false;
  }

  /// Semantics actions that screen readers also send by themselves, when the
  /// screen changes, rather than only when the user acts.
  static const Set<SemanticsAction> _focusActions = <SemanticsAction>{
    SemanticsAction.didGainAccessibilityFocus,
    SemanticsAction.didLoseAccessibilityFocus,
    SemanticsAction.focus,
    SemanticsAction.showOnScreen,
  };

  void _handleSemanticsAction(SemanticsActionEvent event) {
    _handleActivity(canEndIdle: !_focusActions.contains(event.type));
  }

  /// Called when a screen reader moves its focus. Some platforms, such as iOS,
  /// report most focus moves only this way, not as a semantics action.
  void _handleAccessibilityFocus() => _handleActivity(canEndIdle: false);

  void _handlePointerEvent(PointerEvent event) => _handleActivity();

  bool _handleKeyEvent(KeyEvent event) {
    _handleActivity();
    // Never mark the event as handled, so it still reaches the rest of the
    // app.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Checked here rather than in the constructor, which is const, or in the
    // lifecycle methods, which must not throw.
    assert(
      widget.idleTime > Duration.zero,
      'IdleDetector.idleTime must be greater than Duration.zero, '
      'but was ${widget.idleTime}.',
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerEvent,
      onPointerMove: _handlePointerEvent,
      onPointerUp: _handlePointerEvent,
      onPointerHover: _handlePointerEvent,
      onPointerSignal: _handlePointerEvent,
      onPointerPanZoomStart: _handlePointerEvent,
      onPointerPanZoomUpdate: _handlePointerEvent,
      onPointerPanZoomEnd: _handlePointerEvent,
      child: widget.child,
    );
  }
}

/// Reports activity to an [IdleDetector] from code and reads its idle state.
///
/// Pass the controller to [IdleDetector.controller]. Use it for activity the
/// detector can't see, such as typing on an on-screen keyboard:
///
/// ```dart
/// final idleController = IdleDetectorController();
///
/// // ...
///
/// TextField(
///   onChanged: (_) => idleController.reset(),
/// )
/// ```
///
/// A controller is meant for one [IdleDetector] at a time. If several
/// detectors use it at once, [reset] applies to all of them, and [isIdle]
/// reports the one that started using the controller most recently.
final class IdleDetectorController {
  /// Creates a controller to pass to [IdleDetector.controller].
  IdleDetectorController();

  final List<_IdleDetectorState> _states = <_IdleDetectorState>[];

  /// Whether an [IdleDetector] in the tree is using this controller.
  ///
  /// While this is `false`, [isIdle] is `false` and [reset] does nothing.
  bool get isAttached => _states.isNotEmpty;

  /// Whether the user is currently idle: [IdleDetector.idleTime] has passed
  /// without activity, and nothing has ended the idle period since.
  ///
  /// Activity that ends the idle period also calls [IdleDetector.onActive].
  /// Disabling the detector ends it too, but without calling
  /// [IdleDetector.onActive]. Screen reader focus moves don't end it.
  ///
  /// If several detectors use this controller, this reports the one that
  /// started using it most recently.
  bool get isIdle => _states.isNotEmpty && _states.last._isIdle;

  /// Counts as user activity and restarts the countdown.
  ///
  /// Behaves like a real interaction: if the user was idle,
  /// [IdleDetector.onActive] is called.
  ///
  /// Does nothing if the detector is disabled, the controller is not
  /// attached, or the detector is waiting for the app to become visible (see
  /// [IdleDetector]).
  void reset() {
    for (final state in List<_IdleDetectorState>.of(_states)) {
      state._handleActivity();
    }
  }

  void _attach(_IdleDetectorState state) {
    if (!_states.contains(state)) {
      _states.add(state);
    }
  }

  void _detach(_IdleDetectorState state) {
    _states.remove(state);
  }
}
