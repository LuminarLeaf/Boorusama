// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'foundation/errors/handlers.dart';
import 'foundation/loggers.dart';
import 'settings/providers.dart';
import 'settings/settings.dart';
import 'tracking/types.dart';

Future<Tracker> initializeTracking(
  Settings settings, {
  Logger? logger,
}) async =>
    new DummyTracker();

final trackerProvider = FutureProvider<Tracker>((ref) async {
  final tracker = new DummyTracker();

  initializeErrorHandlers(tracker.reporter);

  return tracker;
});
