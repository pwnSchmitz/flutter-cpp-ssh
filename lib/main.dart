import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'app/ssh_manager_app.dart';

void main() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    debugPrint('[${record.loggerName}] ${record.level.name}: ${record.message}');
    if (record.error != null) debugPrint('Error: ${record.error}');
    if (record.stackTrace != null) debugPrint('Stack: ${record.stackTrace}');
  });

  runApp(const SSHManagerApp());
}