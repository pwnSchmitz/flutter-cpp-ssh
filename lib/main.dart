import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';
import 'search_service.dart';
import 'models/search_result.dart';
import 'screens/search_screen.dart';

// 🔐 Глобальный экземпляр для безопасного хранения
const _storage = FlutterSecureStorage();

// ─────────────────────────────────────────────
// 🚀 ТОЧКА ВХОДА
// ─────────────────────────────────────────────
void main() {
  // 🪵 Настройка логирования
  Logger.root.level = Level.INFO; // Уровень: ALL, INFO, WARNING, SEVERE
  Logger.root.onRecord.listen((record) {
    debugPrint('[${record.loggerName}] ${record.level.name}: ${record.message}');
    if (record.error != null) debugPrint('Error: ${record.error}');
    if (record.stackTrace != null) debugPrint('Stack: ${record.stackTrace}');
  });

  runApp(const SSHManagerApp());
}

class SSHManagerApp extends StatelessWidget {
  const SSHManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionProvider()),
        Provider<SearchService>(
          create: (_) => SearchService()..init(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: 'SSH & File Search',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
          primaryColor: const Color(0xFF00E5FF),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00E5FF),
            secondary: Color(0xFF7C4DFF),
            surface: Color(0xFF1E1E1E),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E1E1E),
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF2D2D2D),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          cardTheme: CardThemeData(color: const Color(0xFF1E1E1E), elevation: 2),
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 🧭 ГЛАВНАЯ НАВИГАЦИЯ
// ─────────────────────────────────────────────
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    ConnectionListScreen(),
    SearchScreen(), // ✅ Теперь SearchScreen берёт сервис из Provider
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.cloud), label: 'SSH'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Поиск'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 📋 ЭКРАН СПИСКА ПОДКЛЮЧЕНИЙ
// ─────────────────────────────────────────────
class ConnectionListScreen extends StatelessWidget {
  const ConnectionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connections = context.watch<ConnectionProvider>().connections;

    return Scaffold(
      appBar: AppBar(title: const Text('🔐 SSH Подключения')),
      body: connections.isEmpty ? _buildEmptyState(context) : _buildConnectionList(context, connections),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openConnectionDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Добавить сервер'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text('Нет подключений', style: TextStyle(fontSize: 18, color: Colors.grey[400])),
          const SizedBox(height: 8),
          Text('Нажмите + чтобы добавить первый сервер', style: TextStyle(fontSize: 14, color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: () => _openConnectionDialog(context, null), icon: const Icon(Icons.add), label: const Text('Добавить подключение')),
        ],
      ),
    );
  }

  Widget _buildConnectionList(BuildContext context, List<SSHConnection> connections) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: connections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final conn = connections[index];
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(conn.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('${conn.username}@${conn.host}:${conn.port}', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                if (conn.keyLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(Icons.key, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text('Ключ: ${conn.keyLabel}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ]),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openConnectionDialog(context, conn)),
                IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => _confirmDelete(context, conn)),
              ],
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TerminalScreen(connection: conn))),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, SSHConnection conn) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('Удалить подключение?'),
      content: Text('Вы уверены, что хотите удалить "${conn.label}"?\n\nКлюч будет безвозвратно удалён.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        ElevatedButton(
          onPressed: () { context.read<ConnectionProvider>().removeConnection(conn.id); Navigator.pop(ctx); },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Удалить'),
        ),
      ],
    ));
  }

  void _openConnectionDialog(BuildContext context, SSHConnection? existing) {
    showDialog(context: context, builder: (ctx) => ConnectionDialog(connection: existing));
  }
}

// ─────────────────────────────────────────────
// ✏️ ДИАЛОГ ДОБАВЛЕНИЯ/РЕДАКТИРОВАНИЯ
// ─────────────────────────────────────────────
class ConnectionDialog extends StatefulWidget {
  final SSHConnection? connection;
  const ConnectionDialog({super.key, this.connection});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _keyController;
  String? _keyLabel;

  @override
  void initState() {
    super.initState();
    final c = widget.connection;
    _labelController = TextEditingController(text: c?.label ?? '');
    _hostController = TextEditingController(text: c?.host ?? '');
    _portController = TextEditingController(text: c?.port.toString() ?? '22');
    _usernameController = TextEditingController(text: c?.username ?? '');
    _keyController = TextEditingController();
    _keyLabel = c?.keyLabel ?? 'key_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _labelController.dispose(); _hostController.dispose();
    _portController.dispose(); _usernameController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.connection != null;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(isEdit ? '✏️ Редактировать' : '➕ Добавить подключение'),
      content: SingleChildScrollView(
        child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: _labelController, decoration: const InputDecoration(labelText: 'Название *', prefixIcon: Icon(Icons.label)), validator: (v) => v?.isEmpty ?? true ? 'Введите название' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _hostController, decoration: const InputDecoration(labelText: 'Хост *', prefixIcon: Icon(Icons.dns), hintText: '192.168.1.1'), validator: (v) => v?.isEmpty ?? true ? 'Введите хост' : null),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _portController, decoration: const InputDecoration(labelText: 'Порт', prefixIcon: Icon(Icons.numbers), hintText: '22'), keyboardType: TextInputType.number, validator: (v) { if (v?.isEmpty ?? true) return null; final p = int.tryParse(v!); if (p == null || p < 1 || p > 65535) return '1-65535'; return null; })),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Пользователь *', prefixIcon: Icon(Icons.person), hintText: 'root'), validator: (v) => v?.isEmpty ?? true ? 'Введите пользователя' : null)),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Colors.grey),
          const SizedBox(height: 8),
          const Text('🔐 SSH ключ (опционально)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (isEdit && widget.connection?.keyLabel != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Текущий ключ: ${widget.connection!.keyLabel}', style: TextStyle(fontSize: 12, color: Colors.grey[400]))),
          TextFormField(controller: _keyController, decoration: const InputDecoration(labelText: 'Приватный ключ (OpenSSH)', prefixIcon: Icon(Icons.key), hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...'), maxLines: 5, style: GoogleFonts.jetBrainsMono(fontSize: 10)),
          const SizedBox(height: 4),
          Text('💡 Ключ будет зашифрован и сохранён в безопасном хранилище устройства', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        ElevatedButton(onPressed: _saveConnection, child: Text(isEdit ? 'Сохранить' : 'Добавить')),
      ],
    );
  }

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ConnectionProvider>();
    final privateKey = _keyController.text.trim();
    final connection = SSHConnection(
      id: widget.connection?.id ?? SSHConnection.generateId(),
      label: _labelController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text.trim(),
      keyLabel: privateKey.isNotEmpty ? _keyLabel : widget.connection?.keyLabel,
    );
    try {
      if (privateKey.isNotEmpty) await connection.savePrivateKey(privateKey);
      if (widget.connection != null) provider.updateConnection(connection);
      else provider.addConnection(connection);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red));
    }
  }
}

// ─────────────────────────────────────────────
// 💻 ЭКРАН ТЕРМИНАЛА
// ─────────────────────────────────────────────
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
  SSHClient? _client;
  SSHSession? _shellSession;
  StreamSubscription? _stdoutSubscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _lastCommandOutput = '';
  bool _isWaitingForOutput = false;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(duration: const Duration(seconds: 5), vsync: this)..repeat();
    _colorController.addListener(() {
      if (mounted) setState(() => _currentSystemColor = HSLColor.fromAHSL(1.0, _colorController.value * 360, 0.8, 0.5).toColor());
    });
    _addWelcomeMessage();
    WidgetsBinding.instance.addPostFrameCallback((_) { _scrollToBottom(); _focusNode.requestFocus(); _connectToSsh(); });
  }

  Future<void> _connectToSsh() async {
    if (_isConnected || _isConnecting) return;
    setState(() { _isConnecting = true; _addSystemMessage("Connecting to ${widget.connection.host}:${widget.connection.port}..."); });
    try {
      final socket = await SSHSocket.connect(widget.connection.host, widget.connection.port);
      String? privateKey = await widget.connection.loadPrivateKey();
      List<SSHKeyPair> keyPairs = [];
      if (privateKey != null && privateKey.isNotEmpty) keyPairs = SSHKeyPair.fromPem(privateKey);
      _client = SSHClient(socket, username: widget.connection.username, identities: keyPairs);
      await _client!.authenticated;
      
      // 🔥 Увеличили размер терминала (без параметра terminal)
      _shellSession = await _client!.shell(pty: SSHPtyConfig(width: 120, height: 40));
      
      // 🔥 Подписка на stdout с обработкой ошибок
      _stdoutSubscription = _shellSession!.stdout.listen((chunk) {
        final cleanText = _stripAnsiCodes(utf8.decode(chunk, allowMalformed: true));
        if (_isWaitingForOutput) _lastCommandOutput += cleanText;
      }, onError: (error) { if (mounted) setState(() => _addLine("Stream error: $error", isSystem: true)); });
      
      // 🔥 Дополнительно: слушаем stderr если есть
      if (_shellSession!.stderr != null) {
        _shellSession!.stderr!.listen((chunk) {
          if (_isWaitingForOutput) _lastCommandOutput += utf8.decode(chunk, allowMalformed: true);
        });
      }
      
      // 🔥 Увеличили задержку для инициализации оболочки
      await Future.delayed(const Duration(milliseconds: 1000));
      
      setState(() { _isConnected = true; _isConnecting = false; _addSystemMessage("✓ Connection established."); _addPromptLine(); });
    } catch (e) {
      setState(() { _isConnecting = false; _addSystemMessage("✗ Connection failed: $e"); _addPromptLine(); });
    }
  }

  @override
  void dispose() {
    _stdoutSubscription?.cancel(); _shellSession?.close(); _client?.close();
    _scrollController.dispose(); _focusNode.dispose(); _colorController.dispose();
    super.dispose();
  }

  String _stripAnsiCodes(String text) {
    String result = text
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[a-zA-Z]'), '')      // CSI-коды (цвета, курсор)
        .replaceAll(RegExp(r'\x1B\([a-zA-Z0-9]'), '')           // G0/G1 набор символов
        .replaceAll(RegExp(r'\x1B[@-Z\\-_]'), '')               // Другие управляющие
        .replaceAll(RegExp(r'[\r\x07]'), '')                    // CR и BEL
        // 🔥 НОВОЕ: Удаляем OSC-коды (заголовок окна терминала): \x1B]0;текст\x07
        .replaceAll(RegExp(r'\x1B\][0-9];[^\x07\x1B]*([\x07]|\x1B\\)'), '');
    
    // 🔥 Фильтруем системный мусор (dbus, systemd, journal)
    final lines = result.split('\n');
    final filtered = lines.where((line) {
      final trimmed = line.trim();
      // Пропускаем строки с отладочной информацией
      if (trimmed.contains('dbus') && trimmed.contains('machineid')) return false;
      if (trimmed.contains('start=') && trimmed.contains('pid=')) return false;
      if (trimmed.startsWith('3008;')) return false;
      if (trimmed.contains('journal') || trimmed.contains('systemd')) return false;
      if (trimmed.contains('type=command') && trimmed.contains('cwd=')) return false;
      return true;
    });
    
    return filtered.join('\n');
  }

  void _addLine(String text, {bool isSystem = false, bool isWelcome = false, bool isOutput = false}) {
    if (!mounted) return;
    _lines.add(TerminalLine(text: isOutput || isSystem ? _stripAnsiCodes(text) : text, isSystem: isSystem, isWelcome: isWelcome, isOutput: isOutput));
    _scrollToBottom();
  }
  void _addPromptLine() { if (mounted) { _lines.add(TerminalLine(text: _currentInput, isPrompt: true)); _scrollToBottom(); } }
  void _updatePromptLine() { if (_lines.isNotEmpty && _lines.last.isPrompt) { setState(() => _lines.last.text = _currentInput); _scrollToBottom(); } }
  void _addSystemMessage(String text) => _addLine(text, isSystem: true);
  void _addWelcomeMessage() {
    _addLine("", isWelcome: true);
    _addLine("⠄⠄⠄⠄⠄                            SSH Terminal", isWelcome: true);
    _addLine("⠄⠄⣷⣦⠄                            Host: ${widget.connection.host}:${widget.connection.port}", isWelcome: true);
    _addLine("⠄⠄⠄⠄                            User: ${widget.connection.username}", isWelcome: true);
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
    if (_currentInput.trim().isEmpty) { _currentInput = ''; _cursorPosition = 0; _updatePromptLine(); return; }
    final command = _currentInput;
    if (_lines.isNotEmpty && _lines.last.isPrompt) setState(() => _lines.removeLast());
    setState(() => _lines.add(TerminalLine(prompt: "${widget.connection.username}@${widget.connection.host}:~\$ ", command: command, isCommandLine: true)));
    _currentInput = ''; _cursorPosition = 0;
    await _executeRemoteCommand(command);
  }
  
  Future<void> _executeRemoteCommand(String command) async {
    final trimmedCmd = command.trim();
    if (trimmedCmd == 'clear' || trimmedCmd == 'cls') {
      setState(() => _lines.clear());
      _addPromptLine();
      return;
    }
    if (!_isConnected || _shellSession == null) { _addLine("Error: Not connected.", isOutput: true); _addPromptLine(); return; }
    try {
      _lastCommandOutput = ''; _isWaitingForOutput = true;
      _shellSession!.write(utf8.encode('$command\n'));
      
      // 🔥 Увеличили задержку + проверка если вывод пустой
      await Future.delayed(const Duration(milliseconds: 800));
      if (_lastCommandOutput.isEmpty) await Future.delayed(const Duration(milliseconds: 400));
      
      if (_lastCommandOutput.isNotEmpty) {
        final cleanOutput = _lastCommandOutput.split('\n').where((line) {
          final t = line.trim();
          if (t.isEmpty || t == command) return false;
          if (t.contains('@') && (t.contains(r'$') || t.contains('#'))) return false;
          if (t.startsWith('[') || t.startsWith('─') || t.startsWith('┌') || t.startsWith('└')) return false;
          if (t.contains('dbus') && t.contains('machineid')) return false;
          if (t.contains('start=') && t.contains('pid=')) return false;
          if (t.startsWith('3008;')) return false;
          if (t.contains('type=command') && t.contains('cwd=')) return false;
          if (t.contains('journal') || t.contains('systemd')) return false;
          return true;
        }).join('\n');
        
        // 🔥 Показываем вывод даже если фильтрация убрала всё, но данные были
        final outputToShow = cleanOutput.trim().isNotEmpty ? cleanOutput.trim() : _lastCommandOutput.trim();
        if (outputToShow.isNotEmpty) _addLine(outputToShow, isOutput: true);
      }
      _isWaitingForOutput = false;
    } catch (e) { _addLine("Error: $e", isSystem: true); } finally { _addPromptLine(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.connection.label),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { _stdoutSubscription?.cancel(); _shellSession?.close(); _client?.close(); Navigator.pop(context); }),
        actions: [IconButton(icon: Icon(_isConnected ? Icons.circle : Icons.circle_outlined, color: _isConnected ? Colors.green : Colors.grey), onPressed: null, tooltip: _isConnected ? 'Подключено' : 'Отключено'), const SizedBox(width: 8)],
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
            
            // 🔥 ОБНОВЛЁННАЯ ПРОВЕРКА ДЛЯ КИРИЛЛИЦЫ:
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
        child: GestureDetector(onTap: () => _focusNode.requestFocus(), child: Container(color: Colors.black, child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(12.0), itemCount: _lines.length, itemBuilder: (context, index) => _buildTerminalLine(_lines[index], index == _lines.length - 1)))),
      ),
    );
  }

  Widget _buildTerminalLine(TerminalLine line, bool isLastPrompt) {
    if (line.isCommandLine) return Padding(padding: const EdgeInsets.only(bottom: 2.0), child: RichText(text: TextSpan(children: [
      TextSpan(text: line.prompt, style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.4, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
      TextSpan(text: line.command, style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.4, color: Colors.red, fontWeight: FontWeight.bold)),
    ])));
    if (line.isPrompt) return Padding(padding: const EdgeInsets.only(bottom: 2.0), child: RichText(text: TextSpan(children: [
      TextSpan(text: "${widget.connection.username}@${widget.connection.host}:~\$ ", style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.4, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
      TextSpan(text: line.text, style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.4, color: Colors.red)),
      if (isLastPrompt && _focusNode.hasFocus) WidgetSpan(child: Container(width: 8, height: 18, color: Colors.white.withOpacity(0.8), margin: const EdgeInsets.only(left: 1))),
    ])));
    Color textColor = line.isWelcome ? _currentSystemColor : (line.isSystem ? Colors.redAccent : Colors.white);
    return Padding(padding: const EdgeInsets.only(bottom: 2.0), child: SelectableText(line.text, style: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.4, color: textColor, fontWeight: line.isWelcome ? FontWeight.w600 : FontWeight.normal, shadows: line.isWelcome ? [Shadow(color: textColor.withOpacity(0.5), blurRadius: 4)] : null)));
  }
}

// ─────────────────────────────────────────────
// 📦 МОДЕЛИ
// ─────────────────────────────────────────────
class SSHConnection {
  final String id, label, host, username;
  final int port;
  final String? keyLabel;
  SSHConnection({required this.id, required this.label, required this.host, this.port = 22, required this.username, this.keyLabel});
  static String generateId() => DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(1000).toString().padLeft(3, '0');
  Future<void> savePrivateKey(String k) async => await _storage.write(key: 'ssh_key_$keyLabel', value: k);
  Future<String?> loadPrivateKey() async => keyLabel != null ? await _storage.read(key: 'ssh_key_$keyLabel') : null;
  Future<void> deletePrivateKey() async { if (keyLabel != null) await _storage.delete(key: 'ssh_key_$keyLabel'); }
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'host': host, 'port': port, 'username': username, 'keyLabel': keyLabel};
  factory SSHConnection.fromJson(Map<String, dynamic> j) => SSHConnection(id: j['id'], label: j['label'], host: j['host'], port: j['port'] ?? 22, username: j['username'], keyLabel: j['keyLabel']);
}

class ConnectionProvider extends ChangeNotifier {
  final List<SSHConnection> _connections = [];
  void addConnection(SSHConnection c) { _connections.add(c); notifyListeners(); }
  void updateConnection(SSHConnection c) { final i = _connections.indexWhere((x) => x.id == c.id); if (i != -1) { _connections[i] = c; notifyListeners(); } }
  void removeConnection(String id) async { final c = _connections.firstWhere((x) => x.id == id); await c.deletePrivateKey(); _connections.removeWhere((x) => x.id == id); notifyListeners(); }
  List<SSHConnection> get connections => List.unmodifiable(_connections);
}

class TerminalLine {
  String text; bool isPrompt, isSystem, isWelcome, isOutput, isCommandLine; String? prompt, command;
  TerminalLine({this.text = '', this.isSystem = false, this.isWelcome = false, this.isOutput = false, this.isPrompt = false, this.isCommandLine = false, this.prompt, this.command});
}