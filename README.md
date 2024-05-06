This packages provides a widget [IdleDetector] that detects when a user stops interacting with your app.

## Usage

Wrap your app in the [IdleDetector] widget and do something with the callback.

```dart
IdleDetector(
    idleTime: const Duration(minutes: 1),
    onIdle: () {
        print('The user has not interacted with the app for 1 minute.');
    },
    child: Center(
        child: Text('Hello World'),
    ),
);
```
