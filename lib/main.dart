import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'dart:async';
import 'dart:convert';

void main() {
  runApp(const SshTerminalApp());
}

class SshTerminalApp extends StatelessWidget {
  const SshTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RGB SSH Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const TerminalScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// 📋 НАСТРОЙКИ ПОДКЛЮЧЕНИЯ
// ─────────────────────────────────────────────
const String sshHost = '192.168.1.31';
const int sshPort = 22;
const String sshUser = 'kali';

const String sshPrivateKey = '''-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB... (ВАШ КЛЮЧ) ...
-----END OPENSSH PRIVATE KEY-----''';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<TerminalLine> _lines = [];
  String _currentInput = '';
  int _cursorPosition = 0;
  
  late AnimationController _colorController;
  Color _currentSystemColor = Colors.grey;

  SSHClient? _client;
  SSHSession? _shellSession;
  StreamSubscription? _stdoutSubscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  
  // Для фильтрации вывода
  String _lastCommandOutput = '';
  bool _isWaitingForOutput = false;
  String _commandSent = '';

  @override
  void initState() {
    super.initState();

    _colorController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat();

    _colorController.addListener(() {
      if (mounted) {
        setState(() {
          _currentSystemColor = _generateRainbowColor(_colorController.value);
        });
      }
    });

    _addWelcomeMessage();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
      _focusNode.requestFocus();
      _connectToSsh();
    });
  }

  Future<void> _connectToSsh() async {
    if (_isConnected || _isConnecting) return;

    setState(() {
      _isConnecting = true;
      _addSystemMessage("Connecting to $sshHost:$sshPort...");
    });

    try {
      final socket = await SSHSocket.connect(sshHost, sshPort);
      final keyPairs = SSHKeyPair.fromPem(sshPrivateKey);
      
      _client = SSHClient(
        socket,
        username: sshUser,
        identities: [...keyPairs],
      );

      await _client!.authenticated;

      _shellSession = await _client!.shell(
        pty: SSHPtyConfig(
          width: 80,
          height: 24,
        ),
      );

      // Подписываемся на вывод
      _stdoutSubscription = _shellSession!.stdout.listen((chunk) {
        final text = utf8.decode(chunk);
        final cleanText = _stripAnsiCodes(text);
        
        // Если ждем вывод команды - накапливаем его
        if (_isWaitingForOutput) {
          _lastCommandOutput += cleanText;
        }
      }, onError: (error) {
        if (mounted) {
          setState(() {
            _addLine("Stream error: $error", isSystem: true);
          });
        }
      });

      await Future.delayed(Duration(milliseconds: 800));

      setState(() {
        _isConnected = true;
        _isConnecting = false;
        _addSystemMessage("✓ Connection established.");
        _addPromptLine();
      });

    } catch (e) {
      setState(() {
        _isConnecting = false;
        _addSystemMessage("✗ Connection failed: $e");
        _addPromptLine();
      });
    }
  }

  @override
  void dispose() {
    _stdoutSubscription?.cancel();
    _shellSession?.close();
    _client?.close();
    _scrollController.dispose();
    _focusNode.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Color _generateRainbowColor(double value) {
    return HSLColor.fromAHSL(
      1.0,
      value * 360,
      0.8,
      0.5,
    ).toColor();
  }

  // Удаление ANSI-кодов
  String _stripAnsiCodes(String text) {
    String result = text;
    result = result.replaceAll(RegExp(r'\x1B\[[0-9;?]*[a-zA-Z]'), '');
    result = result.replaceAll(RegExp(r'\x1B\([a-zA-Z0-9]'), '');
    result = result.replaceAll(RegExp(r'\x1B[@-Z\\-_]'), '');
    result = result.replaceAll(RegExp(r'[\r\x07]'), '');
    return result;
  }

  // Обработка вывода команды
  String _processCommandOutput(String output, String command) {
    List<String> lines = output.split('\n');
    List<String> filteredLines = [];
    
    for (String line in lines) {
      String trimmed = line.trim();
      
      if (trimmed.isEmpty) continue;
      if (trimmed == command) continue;
      if (trimmed.contains('@') && (trimmed.contains('\$') || trimmed.contains('#'))) continue;
      if (trimmed.startsWith('[') || trimmed.startsWith(']')) continue;
      if (trimmed.startsWith('─') || trimmed.startsWith('┌') || trimmed.startsWith('└')) continue;
      if (trimmed.contains('kali@') && trimmed.contains(':')) continue;
      
      filteredLines.add(trimmed);
    }
    
    return filteredLines.join('\n');
  }

  void _addLine(String text, {bool isSystem = false, bool isWelcome = false, bool isOutput = false}) {
    if (!mounted) return;
    
    String cleanText = text;
    if (isOutput || isSystem) {
      cleanText = _stripAnsiCodes(text);
    }
    
    _lines.add(TerminalLine(
      text: cleanText,
      isSystem: isSystem,
      isWelcome: isWelcome,
      isOutput: isOutput,
    ));
    _scrollToBottom();
  }

  void _addPromptLine() {
    if (!mounted) return;
    _lines.add(TerminalLine(
      text: _currentInput,
      isPrompt: true,
    ));
  }

  void _updatePromptLine() {
    if (_lines.isNotEmpty && _lines.last.isPrompt) {
      setState(() {
        _lines.last.text = _currentInput;
      });
      _scrollToBottom();
    }
  }

  void _addSystemMessage(String text) => _addLine(text, isSystem: true);

  void _addWelcomeMessage() {
    _addLine("", isWelcome: true);
    _addLine("⠄⠄⠄⠄⠄                            RGB SSH Terminal", isWelcome: true);
    _addLine("⠄⠄⣷⣦⠄                            Host: $sshHost:$sshPort", isWelcome: true);
    _addLine("⠄⠄⠄⠄                            User: $sshUser", isWelcome: true);
    _addLine("", isWelcome: true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertCharacter(String character) {
    if (_cursorPosition == _currentInput.length) {
      _currentInput += character;
    } else {
      _currentInput = _currentInput.substring(0, _cursorPosition) + 
                      character + 
                      _currentInput.substring(_cursorPosition);
    }
    _cursorPosition++;
    _updatePromptLine();
  }

  void _deleteCharacter() {
    if (_cursorPosition > 0) {
      _currentInput = _currentInput.substring(0, _cursorPosition - 1) + 
                      _currentInput.substring(_cursorPosition);
      _cursorPosition--;
      _updatePromptLine();
    }
  }

  void _handleSubmitted() async {
    if (_currentInput.trim().isEmpty) {
      _currentInput = '';
      _cursorPosition = 0;
      _updatePromptLine();
      return;
    }

    final command = _currentInput;
    
    if (_lines.isNotEmpty && _lines.last.isPrompt) {
      setState(() => _lines.removeLast());
    }
    
    setState(() {
      _lines.add(TerminalLine(
        prompt: "$sshUser@$sshHost:~\$ ",
        command: command,
        isCommandLine: true,
      ));
    });
    
    _currentInput = '';
    _cursorPosition = 0;
    
    await _executeRemoteCommand(command);
  }

  Future<void> _executeRemoteCommand(String command) async {
    if (!_isConnected || _shellSession == null) {
      _addLine("Error: Not connected.", isOutput: true);
      _addPromptLine();
      return;
    }

    try {
      _lastCommandOutput = '';
      _isWaitingForOutput = true;
      _commandSent = command;
      
      _shellSession!.write(utf8.encode('$command\n'));
      
      await Future.delayed(Duration(milliseconds: 500));
      
      if (_lastCommandOutput.isNotEmpty) {
        String cleanOutput = _processCommandOutput(_lastCommandOutput, command);
        if (cleanOutput.trim().isNotEmpty) {
          _addLine(cleanOutput.trim(), isOutput: true);
        }
      }
      
      _isWaitingForOutput = false;
      
    } catch (e) {
      _addLine("Error: $e", isSystem: true);
    } finally {
      _addPromptLine();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              _handleSubmitted();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
              _deleteCharacter();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                _currentInput = '';
                _cursorPosition = 0;
                _updatePromptLine();
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (_cursorPosition > 0) {
                setState(() => _cursorPosition--);
                _updatePromptLine();
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (_cursorPosition < _currentInput.length) {
                setState(() => _cursorPosition++);
                _updatePromptLine();
              }
              return KeyEventResult.handled;
            } else {
              final String? character = event.character;
              if (character != null && character.isNotEmpty && !character.contains(RegExp(r'[^\x20-\x7E]'))) {
                _insertCharacter(character);
                return KeyEventResult.handled;
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Container(
            color: Colors.black,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12.0),
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final line = _lines[index];
                final isLastPrompt = index == _lines.length - 1 && line.isPrompt;
                return _buildTerminalLine(line, isLastPrompt);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalLine(TerminalLine line, bool isLastPrompt) {
    if (line.isCommandLine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: line.prompt,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: line.command,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (line.isPrompt) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: "$sshUser@$sshHost:~\$ ",
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: line.text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.red,
                ),
              ),
              if (isLastPrompt && _focusNode.hasFocus)
                WidgetSpan(
                  child: Container(
                    width: 8,
                    height: 18,
                    color: Colors.white.withOpacity(0.8),
                    margin: const EdgeInsets.only(left: 1),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Color textColor = Colors.white;
    FontWeight fontWeight = FontWeight.normal;

    if (line.isWelcome) {
      textColor = _currentSystemColor;
      fontWeight = FontWeight.w600;
    } else if (line.isSystem) {
      textColor = Colors.redAccent;
      fontWeight = FontWeight.w300;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2.0),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 14.5,
          height: 1.4,
          color: textColor,
          fontWeight: fontWeight,
          shadows: line.isWelcome 
            ? [Shadow(color: textColor.withOpacity(0.5), blurRadius: 4)] 
            : null,
        ),
      ),
    );
  }
}

class TerminalLine {
  String text;
  final bool isSystem;
  final bool isWelcome;
  final bool isOutput;
  bool isPrompt;
  bool isCommandLine;
  String? prompt;
  String? command;

  TerminalLine({
    this.text = '',
    this.isSystem = false,
    this.isWelcome = false,
    this.isOutput = false,
    this.isPrompt = false,
    this.isCommandLine = false,
    this.prompt,
    this.command,
  });
}