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
  final List<TerminalLine> _lines = [];
  String _currentInput = '';
  int _cursorPosition = 0;
  late AnimationController _colorController;
  Color _currentSystemColor = Colors.grey;
  final SSHService _sshService = SSHService();
  bool _isConnecting = false;
  String _lastSentCommand = '';

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(duration: const Duration(seconds: 5), vsync: this)..repeat();
    _colorController.addListener(() {
      if (mounted) setState(() => _currentSystemColor = HSLColor.fromAHSL(1.0, _colorController.value * 360, 0.8, 0.5).toColor());
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
      _addSystemMessage("Connecting to ${widget.connection.host}:${widget.connection.port}...");
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
          if (mounted) setState(() => _addLine("Stream error: $error", isSystem: true));
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
    _colorController.dispose();
    super.dispose();
  }

  void _addLine(String text, {bool isSystem = false, bool isWelcome = false, bool isOutput = false}) {
    if (!mounted) return;
    _lines.add(TerminalLine(text: text, isSystem: isSystem, isWelcome: isWelcome, isOutput: isOutput));
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
    _addLine("_______________________________________________________________________________", isWelcome: true);
    _addLine("", isWelcome: true);
    _addLine("SSH Terminal", isWelcome: true);
    _addLine("Host: ${widget.connection.host}:${widget.connection.port}", isWelcome: true);
    _addLine("User: ${widget.connection.username}", isWelcome: true);
    _addLine("", isWelcome: true);
    _addLine("_______________________________________________________________________________", isWelcome: true);
            _addLine("", isWelcome: true);
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }
  
  void _insertCharacter(String character) {
    _currentInput = _cursorPosition == _currentInput.length ? _currentInput + character : _currentInput.substring(0, _cursorPosition) + character + _currentInput.substring(_cursorPosition);
    _cursorPosition++; _updatePromptLine();
  }
  
  void _deleteCharacter() {
    if (_cursorPosition > 0) {
      _currentInput = _currentInput.substring(0, _cursorPosition - 1) + _currentInput.substring(_cursorPosition);
      _cursorPosition--; _updatePromptLine();
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
  _lastSentCommand = command;
  
  // Обработка clear/cls
  if (command.trim() == 'clear' || command.trim() == 'cls') {
    setState(() {
      _lines.clear();
      _currentInput = ''; 
      _cursorPosition = 0;
      _addPromptLine();
    });
    return;
  }

  // ✅ ОБРАБОТКА nano
  if (command.startsWith('nano ')) {
    final filePath = command.substring(5).trim();
    if (filePath.isEmpty) {
      _addLine("Usage: nano <filename>", isSystem: true);
      _currentInput = ''; 
      _cursorPosition = 0; 
      _updatePromptLine(); 
      return;
    }

    // Открываем редактор
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NanoEditorScreen(
          filePath: filePath,
          sshService: _sshService,
        ),
      ),
    ).then((_) {
      // После закрытия редактора — добавляем prompt
      setState(() => _addPromptLine());
    });

    _currentInput = ''; 
    _cursorPosition = 0; 
    _updatePromptLine(); 
    return;
  }

  // Остальные команды отправляются на сервер
  _currentInput = ''; 
  _cursorPosition = 0;
  _updatePromptLine();
  
  if (_sshService.isConnected) {
    await _executeRemoteCommand(command);
  }
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
      var cleanOutput = TerminalCleaner.cleanOutput(_sshService.lastCommandOutput, command);
      
      final outputLines = cleanOutput.split('\n');
      final filteredLines = <String>[];
      
      for (var line in outputLines) {
        final trimmed = line.trim();
        
        // Пропускаем пустые строки
        if (trimmed.isEmpty) continue;
        
        // Пропускаем prompt'ы
        if (RegExp(r'^[\w\-\.]+@[\w\-\.]+:[^$#]*[#$]\s*$').hasMatch(trimmed)) continue;
        
        // Пропускаем readline артефакты
        if (RegExp(r'^[a-zA-Z]{2,}[>\/]\s*\S').hasMatch(trimmed)) continue;
        if (RegExp(r'^[a-zA-Z]{2,}[>\/]$').hasMatch(trimmed)) continue;
        if (RegExp(r'^[0-9]+;.*[@>]').hasMatch(trimmed)) continue;
        if (trimmed.startsWith(']0;')) continue;
        if (RegExp(r'^[0-9;]+$').hasMatch(trimmed)) continue;
        
        // ✅ ГЛАВНОЕ: Ещё раз проверяем, не является ли это эхом команды
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { _sshService.disconnect(); Navigator.pop(context); }),
        actions: [
          IconButton(
            icon: Icon(_sshService.isConnected ? Icons.circle : Icons.circle_outlined, color: _sshService.isConnected ? Colors.green : Colors.grey),
            onPressed: null,
            tooltip: _sshService.isConnected ? 'Подключено' : 'Отключено',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter) { _handleSubmitted(); return KeyEventResult.handled; }
            if (event.logicalKey == LogicalKeyboardKey.backspace) { _deleteCharacter(); return KeyEventResult.handled; }
            if (event.logicalKey == LogicalKeyboardKey.escape) { setState(() { _currentInput = ''; _cursorPosition = 0; _updatePromptLine(); }); return KeyEventResult.handled; }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _cursorPosition > 0) { setState(() => _cursorPosition--); _updatePromptLine(); return KeyEventResult.handled; }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight && _cursorPosition < _currentInput.length) { setState(() => _cursorPosition++); _updatePromptLine(); return KeyEventResult.handled; }
            
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
    );
  }
}