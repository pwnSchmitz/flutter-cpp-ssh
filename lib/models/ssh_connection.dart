import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _secureStorage = FlutterSecureStorage();

class SSHConnection {
  final String id, label, host, username;
  final int port;
  final String? keyLabel;
  
  SSHConnection({
    required this.id,
    required this.label,
    required this.host,
    this.port = 22,
    required this.username,
    this.keyLabel,
  });
  
  static String generateId() => 
      DateTime.now().millisecondsSinceEpoch.toString() + 
      Random().nextInt(1000).toString().padLeft(3, '0');
  
  Future<void> savePrivateKey(String key) async => 
      await _secureStorage.write(key: 'ssh_key_$keyLabel', value: key);
      
  Future<String?> loadPrivateKey() async => 
      keyLabel != null ? await _secureStorage.read(key: 'ssh_key_$keyLabel') : null;
      
  Future<void> deletePrivateKey() async {
    if (keyLabel != null) await _secureStorage.delete(key: 'ssh_key_$keyLabel');
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'host': host,
    'port': port,
    'username': username,
    'keyLabel': keyLabel,
  };
  
  factory SSHConnection.fromJson(Map<String, dynamic> json) => SSHConnection(
    id: json['id'],
    label: json['label'],
    host: json['host'],
    port: json['port'] ?? 22,
    username: json['username'],
    keyLabel: json['keyLabel'],
  );
}