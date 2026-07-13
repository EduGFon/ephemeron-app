import 'dart:developer' as developer;

class LogEntry {
  final DateTime time;
  final String message;
  final String? error;
  final String? stackTrace;

  LogEntry(this.message, {this.error, this.stackTrace}) : time = DateTime.now();
}

class DevLogger {
  DevLogger._();
  static final List<LogEntry> logs = [];

  static void log(String message) {
    developer.log(message);
    print('[DEV_LOG] $message');
    logs.add(LogEntry(message));
    if (logs.length > 200) logs.removeAt(0);
  }

  static void logError(String message, [dynamic error, StackTrace? stack]) {
    developer.log(message, error: error, stackTrace: stack);
    print('[DEV_ERROR] $message: $error');
    if (stack != null) {
      print(stack);
    }
    logs.add(LogEntry(message, error: error?.toString(), stackTrace: stack?.toString()));
    if (logs.length > 200) logs.removeAt(0);
  }

  static void clear() {
    logs.clear();
  }
}
