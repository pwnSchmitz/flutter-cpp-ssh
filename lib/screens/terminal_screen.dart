import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ssh_connection.dart';
import '../models/terminal_line.dart';
import '../utils/terminal_cleaner.dart';
import '../widgets/terminal_line_builder.dart';
import '../services/ssh_service.dart';
import 'nano_editor_screen.dart';

class TerminalScreen extends StatefulWidget {
  final SSHConnection connection;
  const TerminalScreen({super.key, required this.connection});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _mobileInputController = TextEditingController();
  final List<TerminalLine> _lines = [];
  String _currentInput = '';
  int _cursorPosition = 0;
  late AnimationController _colorController;
  Color _currentSystemColor = Colors.grey;
  final SSHService _sshService = SSHService();
  bool _isConnecting = false;
  String _lastSentCommand = '';

  static const List<String> _quickCommands = [
    'ls -la',
    'cd ~',
    'pwd',
    'top',
    'htop',
    'df -h',
    'free -m',
    'ps aux',
    'tail -f /var/log/syslog',
    'grep',
  ];

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
          _currentSystemColor = HSLColor.fromAHSL(
            1.0,
            _colorController.value * 360,
            0.8,
            0.5,
          ).toColor();
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
    if (_sshService.isConnected || _isConnecting) return;
    setState(() {
      _isConnecting = true;
      _addSystemMessage(
          "Connecting to ${widget.connection.host}:${widget.connection.port}...");
    });
    try {
      await _sshService.connect(widget.connection);

      _sshService.listenToOutput(
        onOutput: (text) {
          final cleaned = TerminalCleaner.cleanOutput(text, _lastSentCommand);
          if (cleaned.trim().isNotEmpty && mounted) {
            setState(() => _addLine(cleaned, isOutput: true));
          }
        },
        onError: (error) {
          if (mounted) setState(() => _addLine(error, isSystem: true));
        },
        onStreamError: (error) {
          if (mounted) {
            setState(() => _addLine("Stream error: $error", isSystem: true));
          }
        },
      );

      await Future.delayed(const Duration(milliseconds: 1000));

      setState(() {
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
    _sshService.disconnect();
    _scrollController.dispose();
    _focusNode.dispose();
    _mobileInputController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _addLine(String text,
      {bool isSystem = false, bool isWelcome = false, bool isOutput = false}) {
    if (!mounted) return;
    _lines.add(TerminalLine(
        text: text,
        isSystem: isSystem,
        isWelcome: isWelcome,
        isOutput: isOutput));
    _scrollToBottom();
  }

  void _addPromptLine() {
    if (mounted) {
      _lines.add(TerminalLine(text: _currentInput, isPrompt: true));
      _scrollToBottom();
    }
  }

  void _updatePromptLine() {
    if (_lines.isNotEmpty && _lines.last.isPrompt) {
      setState(() => _lines.last.text = _currentInput);
      _scrollToBottom();
    }
  }

  void _addSystemMessage(String text) => _addLine(text, isSystem: true);

  void _addWelcomeMessage() {
    _addLine("SSH Terminal", isWelcome: true);
    _addLine("Host: ${widget.connection.host}:${widget.connection.port}",
        isWelcome: true);
    _addLine("User: ${widget.connection.username}", isWelcome: true);
    _addLine("______________________________",
        isWelcome: true);
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
    _currentInput = _cursorPosition == _currentInput.length
        ? _currentInput + character
        : _currentInput.substring(0, _cursorPosition) +
            character +
            _currentInput.substring(_cursorPosition);
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

  void _insertCommandToInput(String command) {
    _mobileInputController.text = command;
    _mobileInputController.selection = TextSelection.fromPosition(
      TextPosition(offset: command.length),
    );

    setState(() {
      _currentInput = command;
      _cursorPosition = command.length;
      _updatePromptLine();
    });

    FocusScope.of(context).unfocus();
    _focusNode.requestFocus();
  }

  void _handleSubmitted() async {
    if (_currentInput.trim().isEmpty) {
      _currentInput = '';
      _cursorPosition = 0;
      _updatePromptLine();
      return;
    }

    final command = _currentInput;
    _lastSentCommand = command;

    if (command.trim() == 'clear' || command.trim() == 'cls') {
      setState(() {
        _lines.clear();
        _currentInput = '';
        _cursorPosition = 0;
        _addPromptLine();
      });
      return;
    }

    if (command.startsWith('nano ')) {
      final filePath = command.substring(5).trim();
      if (filePath.isEmpty) {
        _addLine("Usage: nano <filename>", isSystem: true);
        _currentInput = '';
        _cursorPosition = 0;
        _updatePromptLine();
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NanoEditorScreen(
            filePath: filePath,
            sshService: _sshService,
          ),
        ),
      ).then((_) {
        setState(() => _addPromptLine());
      });

      _currentInput = '';
      _cursorPosition = 0;
      _updatePromptLine();
      return;
    }
    _currentInput = '';
    _cursorPosition = 0;
    _updatePromptLine();

    if (_sshService.isConnected) {
      await _executeRemoteCommand(command);
    }
  }

  void _sendFromMobileBar() {
    final command = _mobileInputController.text.trim();
    if (command.isEmpty) return;

    _currentInput = command;
    _cursorPosition = command.length;
    _handleSubmitted();
    _mobileInputController.clear();
  }

  Future<void> _executeRemoteCommand(String command) async {
    if (!_sshService.isConnected) {
      _addLine("Error: Not connected.", isOutput: true);
      _addPromptLine();
      return;
    }

    try {
      await _sshService.executeCommand(command);

      if (_sshService.lastCommandOutput.isNotEmpty) {
        var cleanOutput =
            TerminalCleaner.cleanOutput(_sshService.lastCommandOutput, command);

        final outputLines = cleanOutput.split('\n');
        final filteredLines = <String>[];

        for (var line in outputLines) {
          final trimmed = line.trim();

          if (trimmed.isEmpty) continue;

          if (RegExp(r'^[\w\-\.]+@[\w\-\.]+:[^$#]*[#$]\s*$').hasMatch(trimmed)) continue;

          if (RegExp(r'^[a-zA-Z]{2,}[>\/]\s*\S').hasMatch(trimmed)) continue;
          if (RegExp(r'^[a-zA-Z]{2,}[>\/]$').hasMatch(trimmed)) continue;
          if (RegExp(r'^[0-9]+;.*[@>]').hasMatch(trimmed)) continue;
          if (trimmed.startsWith(']0;')) continue;
          if (RegExp(r'^[0-9;]+$').hasMatch(trimmed)) continue;

          if (trimmed == command.trim()) continue;
          if (trimmed == '${command.trim()} ') continue;

          filteredLines.add(line);
        }

        final finalOutput = filteredLines.join('\n').trim();
        if (finalOutput.isNotEmpty) {
          setState(() => _addLine(finalOutput, isOutput: true));
        }
      }

      setState(() => _addPromptLine());
    } catch (e) {
      _addLine("Error: $e", isSystem: true);
      _addPromptLine();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.label),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _sshService.disconnect();
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              _sshService.isConnected ? Icons.circle : Icons.circle_outlined,
              color: _sshService.isConnected ? Colors.green : Colors.grey,
            ),
            onPressed: null,
            tooltip: _sshService.isConnected ? 'Подключено' : 'Отключено',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.enter) {
                    _handleSubmitted();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.backspace) {
                    _deleteCharacter();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    setState(() {
                      _currentInput = '';
                      _cursorPosition = 0;
                      _updatePromptLine();
                    });
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                      _cursorPosition > 0) {
                    setState(() => _cursorPosition--);
                    _updatePromptLine();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                      _cursorPosition < _currentInput.length) {
                    setState(() => _cursorPosition++);
                    _updatePromptLine();
                    return KeyEventResult.handled;
                  }

                  final String? character = event.character;
                  if (character != null && character.isNotEmpty) {
                    final code = character.codeUnitAt(0);
                    if (code >= 32 || code == 9) {
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
                    itemBuilder: (context, index) => TerminalLineBuilder.build(
                      _lines[index],
                      index == _lines.length - 1,
                      widget.connection,
                      _focusNode,
                      _currentSystemColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue[700],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: PopupMenuButton<String>(
                    onSelected: _insertCommandToInput,
                    tooltip: 'Быстрые команды',
                    offset: const Offset(0, -40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.grey[850],
                    itemBuilder: (context) => _quickCommands.map((command) {
                      return PopupMenuItem(
                        value: command,
                        child: Text(
                          command,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                        ),
                      );
                    }).toList(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.keyboard_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _mobileInputController,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'Введите команду...',
                        hintStyle: TextStyle(color: Colors.grey[600]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        suffixIcon: _mobileInputController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey),
                                onPressed: () => _mobileInputController.clear(),
                              )
                            : null,
                      ),
                      onSubmitted: (_) => _sendFromMobileBar(),
                      textInputAction: TextInputAction.send,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                ),

                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendFromMobileBar,
                    tooltip: 'Отправить',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}