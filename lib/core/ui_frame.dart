import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Run [action] after the next frame, guaranteeing a frame gets scheduled.
///
/// A bare `addPostFrameCallback` stalls indefinitely while the app is idle
/// (Flutter schedules no frames on its own), so socket-driven UI — snackbars,
/// navigation, dialogs — sits queued until the user next touches the screen.
/// Scheduling a frame first forces the callback to run immediately, while
/// remaining a no-op when a frame is already in flight.
void runAfterFrame(FrameCallback action) {
  SchedulerBinding.instance.scheduleFrame();
  WidgetsBinding.instance.addPostFrameCallback(action);
}
