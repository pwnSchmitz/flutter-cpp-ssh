import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';
import '../models/ssh_connection.dart';
import 'storage_service.dart';

class SSHService {
  SSHClient? _client;
  SSHSession? _shellSession;
  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;
  bool _isConnected = false;
  String _lastCommandOutput = '';
  bool _isWaitingForOutput = false;

  SftpClient? _sftpClient;

  bool get isConnected => _isConnected;
  String get lastCommandOutput => _lastCommandOutput;

  Future<void> connect(SSHConnection connection) async {
    if (_isConnected) {
      throw Exception('Already connected');
    }

    try {
      Logger.root.info('Connecting to ${connection.host}:${connection.port}');
      
      final socket = await SSHSocket.connect(connection.host, connection.port);
      String? privateKey = await StorageService.loadPrivateKey(connection.keyLabel ?? '');
      
      List<SSHKeyPair> keyPairs = [];
      if (privateKey != null && privateKey.isNotEmpty) {
        keyPairs = SSHKeyPair.fromPem(privateKey);
      }

      _client = SSHClient(
        socket,
        username: connection.username,
        identities: keyPairs,
      );

      await _client!.authenticated;
      _sftpClient = await _client!.sftp();
      
      _shellSession = await _client!.shell(
        pty: SSHPtyConfig(width: 120, height: 40),
      );

      _isConnected = true;
      Logger.root.info('Connected successfully with SFTP');
    } catch (e) {
      Logger.root.severe('Connection failed: $e');
      await disconnect();
      rethrow;
    }
  }

  void listenToOutput({
    required Function(String) onOutput,
    required Function(String) onError,
    required Function(dynamic) onStreamError,
  }) {
    if (_shellSession == null) {
      throw Exception('Not connected');
    }

    _stdoutSubscription = _shellSession!.stdout.listen((chunk) {
      if (_isWaitingForOutput) {
        _lastCommandOutput += utf8.decode(chunk, allowMalformed: true);
      } else {
        final text = utf8.decode(chunk, allowMalformed: true);
        if (text.trim().isNotEmpty) {
          onOutput(text);
        }
      }
    }, onError: (error) {
      onStreamError(error);
    });

    if (_shellSession?.stderr != null) {
      _stderrSubscription = _shellSession!.stderr.listen((chunk) {
        if (_isWaitingForOutput) {
          _lastCommandOutput += utf8.decode(chunk, allowMalformed: true);
        } else {
          final errorText = utf8.decode(chunk, allowMalformed: true);
          if (errorText.trim().isNotEmpty) {
            onError(errorText);
          }
        }
      }, onError: (error) {
        onStreamError(error);
      });
    }
  }

  Future<void> executeCommand(String command) async {
    if (!_isConnected || _shellSession == null) {
      throw Exception('Not connected');
    }

    _lastCommandOutput = '';
    _isWaitingForOutput = true;

    try {
      _shellSession!.write(utf8.encode('$command\n'));
      
      await Future.delayed(const Duration(milliseconds: 600));
      int attempts = 0;
      while (_lastCommandOutput.isEmpty && attempts < 8) {
        await Future.delayed(const Duration(milliseconds: 150));
        attempts++;
      }
    } finally {
      _isWaitingForOutput = false;
    }
  }

  void write(String text) {
    _shellSession?.write(utf8.encode(text));
  }

  Future<String> readFile(String remotePath) async {
    if (_sftpClient == null) {
      throw Exception('SFTP not initialized');
    }

    try {
      final file = await _sftpClient!.open(remotePath, mode: SftpFileOpenMode.read);
      
      Uint8List content = await file.readBytes();
      
      await file.close();
      return utf8.decode(content, allowMalformed: true);
    } catch (e) {
      Logger.root.severe('SFTP read error: $e');
      rethrow;
    }
  }

  Future<void> writeFile(String remotePath, String content) async {
    if (_sftpClient == null) {
      throw Exception('SFTP not initialized');
    }

    try {
      final file = await _sftpClient!.open(
        remotePath, 
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
      );
      
      final data = Uint8List.fromList(utf8.encode(content));
      await file.write(Stream.value(data));
      
      await file.close();
      Logger.root.info('File saved via SFTP: $remotePath');
    } catch (e) {
      Logger.root.severe('SFTP write error: $e');
      rethrow;
    }
  }

  Future<bool> fileExists(String remotePath) async {
    if (_sftpClient == null) {
      throw Exception('SFTP not initialized');
    }

    try {
      await _sftpClient!.stat(remotePath);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _shellSession?.close();
    
    _sftpClient?.close();
    _sftpClient = null;
    
    _client?.close();
    _isConnected = false;
    _shellSession = null;
    _client = null;
  }
}