import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:logger/logger.dart';

/// App-wide logger. In release builds the pretty printer is stripped of
/// ANSI colors/emojis, which are only useful in a terminal/logcat during
/// development.
final Logger appLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: !kReleaseMode,
    printEmojis: !kReleaseMode,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);
