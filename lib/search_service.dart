import 'dart:async';
import 'search_ffi.dart';
import 'models/search_result.dart';

class SearchService {
  SearchEngineFFI? _ffi;
  final _resultController = StreamController<SearchResult>.broadcast();
  int _nextRequestId = 1;

  Stream<SearchResult> get results => _resultController.stream;

  Future<void> init() async {
    _ffi = await SearchEngineFFI.create(callback: _onNativeResult);
    _ffi?.init();
    print('[SearchService] Инициализирован');
  }

  void _onNativeResult(
    int requestId,
    bool found,
    String filename,
    String linePreview,
    int lineNumber,
    double searchTimeMs,
  ) {
    if (found) {
      _resultController.add(SearchResult(
        found: true,
        filename: filename,
        linePreview: linePreview,
        lineNumber: lineNumber,
        searchTimeMs: searchTimeMs,
      ));
    }
  }

  int startSearch(List<String> filepaths, String targetNumber) {
    final requestId = _nextRequestId++;
    print('[SearchService] Запуск поиска #$requestId: $targetNumber');
    return _ffi?.start(filepaths, targetNumber) ?? -1;
  }

  void cancelSearch(int requestId) {
    print('[SearchService] Отмена поиска #$requestId');
    _ffi?.cancel(requestId);
  }

  void dispose() {
    _ffi?.cleanup();
    _resultController.close();
  }
}