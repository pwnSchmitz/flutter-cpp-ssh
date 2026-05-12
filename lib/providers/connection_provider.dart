import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import '../models/ssh_connection.dart';
import '../utils/constants.dart';

class ConnectionProvider extends ChangeNotifier {
  final List<SSHConnection> _connections = [];
  bool _isLoading = false;
  
  List<SSHConnection> get connections => List.unmodifiable(_connections);
  bool get isLoading => _isLoading;
  
  Future<void> loadConnections() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$connectionsFileName');
      
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _connections.clear();
        _connections.addAll(jsonList.map((j) => SSHConnection.fromJson(j)));
      }
    } catch (e) {
      Logger.root.severe('Failed to load connections: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> _saveConnectionsToFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$connectionsFileName');
      final jsonList = _connections.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      Logger.root.severe('Failed to save connections: $e');
    }
  }
  
  Future<void> addConnection(SSHConnection connection) async {
    _connections.add(connection);
    await _saveConnectionsToFile();
    notifyListeners();
  }
  
  Future<void> updateConnection(SSHConnection connection) async {
    final index = _connections.indexWhere((x) => x.id == connection.id);
    if (index != -1) {
      final oldConn = _connections[index];
      if (oldConn.keyLabel != connection.keyLabel && oldConn.keyLabel != null) {
        await oldConn.deletePrivateKey();
      }
      _connections[index] = connection;
      await _saveConnectionsToFile();
      notifyListeners();
    }
  }
  
  Future<void> removeConnection(String id) async {
    final conn = _connections.firstWhere((x) => x.id == id, orElse: () => throw Exception('Connection not found'));
    await conn.deletePrivateKey();
    _connections.removeWhere((x) => x.id == id);
    await _saveConnectionsToFile();
    notifyListeners();
  }
}