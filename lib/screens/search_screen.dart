import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../search_service.dart';
import '../models/search_result.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // 💡 В реальном проекте SearchService лучше инжектить через Provider/GetIt
  // Здесь создаём локально для изоляции шага
  final SearchService _service = SearchService();
  
  final TextEditingController _queryController = TextEditingController();
  final List<String> _filePaths = [];
  final List<SearchResult> _results = [];
  
  StreamSubscription<SearchResult>? _resultsSub;
  StreamSubscription<int>? _completeSub;
  int? _activeSearchId;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      await _service.init();
      _resultsSub = _service.results.listen(_onResult, onError: _onError);
      _completeSub = _service.onSearchComplete.listen(_onComplete);
    } catch (e) {
      setState(() => _errorMessage = 'Инициализация поиска: $e');
    }
  }

  void _onResult(SearchResult result) {
    if (mounted) setState(() => _results.add(result));
  }

  void _onError(Object error) {
    if (mounted) setState(() {
      _errorMessage = 'Ошибка потока результатов: $error';
    });
  }

  void _onComplete(int serviceId) {
    if (mounted) setState(() {
      _isSearching = false;
      _activeSearchId = null;
    });
    _showMessage('Поиск завершён. Найдено: ${_results.length}');
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['txt', 'log', 'cpp', 'h', 'dart', 'json', 'yaml', 'md', 'csv'],
    );
    if (result != null) {
      setState(() {
        _filePaths.clear();
        _filePaths.addAll(result.paths.where((p) => p != null).cast<String>());
      });
    }
  }

  Future<void> _startSearch() async {
    setState(() {
      _errorMessage = null;
      _results.clear();
      _isSearching = true;
    });

    try {
      _activeSearchId = _service.startSearch(_filePaths, _queryController.text.trim());
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Не удалось запустить поиск: $e';
      });
    }
  }

  void _cancelSearch() {
    if (_activeSearchId != null) {
      _service.cancelSearch(_activeSearchId!);
      // ⚠️ C++ не отправляет сигнал завершения, поэтому помечаем вручную
      _service.markSearchComplete(_activeSearchId!);
      setState(() {
        _isSearching = false;
        _activeSearchId = null;
      });
      _showMessage('Поиск отменён');
    }
  }

  void _showMessage(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _completeSub?.cancel();
    _service.dispose(); // Закрывает стримы, отменяет нативные запросы, очищает FFI
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔍 Поиск по файлам'),
        backgroundColor: Colors.grey[900],
      ),
      body: Column(
        children: [
          // 📥 Панель управления
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[850],
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        labelText: 'Искомый текст / номер',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isSearching,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _startSearch(),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isSearching ? null : _pickFiles,
                      icon: const Icon(Icons.folder_open),
                      label: Text(_filePaths.isEmpty ? 'Выбрать файлы' : 'Выбрано файлов: ${_filePaths.length}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _filePaths.isEmpty ? Colors.grey : Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSearching ? null : _startSearch,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            child: const Text('▶ Старт'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSearching ? _cancelSearch : null,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('⏹ Отмена'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 🔄 Индикатор загрузки
          if (_isSearching) const LinearProgressIndicator(),

          // ❌ Ошибки
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),

          // 📜 Результаты
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 12),
                        Text('Нет результатов', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final r = _results[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: const Icon(Icons.code, color: Colors.blueAccent),
                          title: SelectableText(
                            r.linePreview,
                            style: GoogleFonts.jetBrainsMono(fontSize: 12.5, height: 1.3),
                            maxLines: 3,
                          ),
                          subtitle: Text(
                            '${r.filename} : строка ${r.lineNumber}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}