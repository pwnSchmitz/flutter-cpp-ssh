import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/ssh_connection.dart';
import '../../providers/connection_provider.dart';

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
    _labelController.dispose(); 
    _hostController.dispose();
    _portController.dispose(); 
    _usernameController.dispose();
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
          TextFormField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Название *', prefixIcon: Icon(Icons.label)),
            validator: (v) => v?.isEmpty ?? true ? 'Введите название' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _hostController,
            decoration: const InputDecoration(labelText: 'Хост *', prefixIcon: Icon(Icons.dns), hintText: '192.168.1.1'),
            validator: (v) => v?.isEmpty ?? true ? 'Введите хост' : null,
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Порт', prefixIcon: Icon(Icons.numbers), hintText: '22'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v?.isEmpty ?? true) return null;
                final p = int.tryParse(v!);
                if (p == null || p < 1 || p > 65535) return '1-65535';
                return null;
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Пользователь *', prefixIcon: Icon(Icons.person), hintText: 'root'),
              validator: (v) => v?.isEmpty ?? true ? 'Введите пользователя' : null,
            )),
          ]),
          const SizedBox(height: 16),
          const Divider(color: Colors.grey),
          const SizedBox(height: 8),
          const Text('🔐 SSH ключ (опционально)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (isEdit && widget.connection?.keyLabel != null)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Текущий ключ: ${widget.connection!.keyLabel}', style: TextStyle(fontSize: 12, color: Colors.grey[400]))),
          TextFormField(
            controller: _keyController,
            decoration: const InputDecoration(labelText: 'Приватный ключ (OpenSSH)', prefixIcon: Icon(Icons.key), hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...'),
            maxLines: 5,
            style: GoogleFonts.jetBrainsMono(fontSize: 10),
          ),
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
      if (widget.connection != null) {
        await provider.updateConnection(connection);
      } else {
        await provider.addConnection(connection);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red));
    }
  }
}