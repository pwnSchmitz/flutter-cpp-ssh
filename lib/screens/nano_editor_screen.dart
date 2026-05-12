import 'package:flutter/material.dart';
import '../services/ssh_service.dart';

class NanoEditorScreen extends StatefulWidget {
  final String filePath;
  final SSHService sshService;

  const NanoEditorScreen({
    super.key,
    required this.filePath,
    required this.sshService,
  });

  @override
  State<NanoEditorScreen> createState() => _NanoEditorScreenState();
}

class _NanoEditorScreenState extends State<NanoEditorScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFileViaSFTP();
  }

  Future<void> _loadFileViaSFTP() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      bool exists = await widget.sshService.fileExists(widget.filePath);
      
      if (!exists) {
        _controller.text = '';
        setState(() => _isLoading = false);
        return;
      }

      String content = await widget.sshService.readFile(widget.filePath);
      _controller.text = content;

    } catch (e) {
      _error = 'Ошибка загрузки: $e';
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveFileViaSFTP() async {
    try {
      setState(() => _isSaving = true);

      String content = _controller.text;
      
      await widget.sshService.writeFile(widget.filePath, content);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Файл успешно сохранён'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = 'Ошибка сохранения: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('nano ${widget.filePath}'),
        backgroundColor: Colors.blue[900],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isSaving ? Icons.hourglass_empty : Icons.save,
              color: Colors.white,
            ),
            onPressed: _isSaving ? null : _saveFileViaSFTP,
            tooltip: 'Сохранить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.red.shade900,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Введите содержимое файла...',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}