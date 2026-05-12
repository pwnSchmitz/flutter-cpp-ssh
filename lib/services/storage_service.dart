import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';
import '../models/ssh_connection.dart';
import '../utils/constants.dart';

const _secureStorage = FlutterSecureStorage();

class StorageService {
  static Future<File> getConnectionsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$connectionsFileName');
  }

  static Future<List<SSHConnection>> loadConnections() async {
    try {
      final file = await getConnectionsFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        return jsonList.map((j) => SSHConnection.fromJson(j)).toList();
      }
    } catch (e) {
      Logger.root.severe('Failed to load connections: $e');
    }
    return [];
  }

  static Future<void> saveConnections(List<SSHConnection> connections) async {
    try {
      final file = await getConnectionsFile();
      final jsonList = connections.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      Logger.root.severe('Failed to save connections: $e');
      rethrow;
    }
  }

  static Future<void> savePrivateKey(String keyLabel, String key) async {
    await _secureStorage.write(key: 'ssh_key_$keyLabel', value: key);
  }

  static Future<String?> loadPrivateKey(String keyLabel) async {
    return await _secureStorage.read(key: 'ssh_key_$keyLabel');
  }

  static Future<void> deletePrivateKey(String keyLabel) async {
    await _secureStorage.delete(key: 'ssh_key_$keyLabel');
  }
}