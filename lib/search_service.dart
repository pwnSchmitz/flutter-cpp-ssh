import 'dart:async';
import 'package:logging/logging.dart';
import 'search_ffi.dart';
import 'models/search_result.dart';

class SearchService {
  static final _log = Logger('SearchService');

  SearchEngineFFI? _ffi;
  
  // Стримы для реактивного UI
  final _resultController = StreamController<SearchResult>.broadcast();
  final _completionController = StreamController<int>.broadcast();
  
  // Маппинг ID: Dart-сторона ↔ Нативная C++ сторона
  final Map<int, int> _serviceToNativeId = {};
  final Map<int, int> _nativeToServiceId = {};
  int _nextServiceId = 1;
  
  bool _isInitialized = false;
  
  // Геттеры для подписки
  Stream<SearchResult> get results => _resultController.stream;
  Stream<int> get onSearchComplete => _completionController.stream;
  bool get isInitialized => _isInitialized;

  /// Инициализация FFI-модуля
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _ffi = await SearchEngineFFI.create(callback: _onNativeCallback);
      _ffi!.init();
      _isInitialized = true;
      _log.info('SearchEngineFFI initialized successfully');
    } catch (e, st) {
      _log.severe('Failed to initialize SearchEngineFFI', e, st);
      rethrow; // Пробрасываем ошибку, чтобы UI мог показать диалог
    }
  }

  /// Запуск поиска. Возвращает serviceId для отслеживания.
  int startSearch(List<String> filepaths, String targetNumber) {
    if (!_isInitialized) {
      throw StateError('SearchService not initialized. Call init() first.');
    }
    if (filepaths.isEmpty) {
      throw ArgumentError('List of file paths cannot be empty');
    }

    final serviceId = _nextServiceId++;
    try {
      final nativeId = _ffi!.start(filepaths, targetNumber);
      
      // Сохраняем двусторонний маппинг
      _serviceToNativeId[serviceId] = nativeId;
      _nativeToServiceId[nativeId] = serviceId;
      
      _log.info('Started search #$serviceId (native: $nativeId) for "$targetNumber" in ${filepaths.length} files');
      return serviceId;
    } catch (e, st) {
      _log.severe('Failed to start search #$serviceId', e, st);
      rethrow;
    }
  }

  /// Отмена поиска по serviceId
  void cancelSearch(int serviceId) {
    final nativeId = _serviceToNativeId[serviceId];
    if (nativeId != null) {
      _ffi?.cancel(nativeId);
      _log.info('Cancelled search #$serviceId');
      _cleanupRequest(serviceId, nativeId);
    } else {
      _log.warning('Attempted to cancel unknown search #$serviceId');
    }
  }

  /// Помечает поиск как завершённый.
  /// ⚠️ Вызывается из UI/сервиса, так как текущий C++ код не шлёт сигнал завершения.
  void markSearchComplete(int serviceId) {
    final nativeId = _serviceToNativeId[serviceId];
    if (nativeId != null) {
      _cleanupRequest(serviceId, nativeId);
      _completionController.add(serviceId);
      _log.info('Search #$serviceId marked as complete');
    }
  }

  /// Внутренний callback из нативного кода
  void _onNativeCallback(
    int nativeId,
    bool found,
    String filename,
    String linePreview,
    int lineNumber,
    double searchTimeMs,
  ) {
    final serviceId = _nativeToServiceId[nativeId];
    if (serviceId == null) {
      _log.warning('Received callback for unknown native ID: $nativeId');
      return;
    }

    if (found && !_resultController.isClosed) {
      _resultController.add(SearchResult(
        found: true,
        filename: filename,
        linePreview: linePreview,
        lineNumber: lineNumber,
        searchTimeMs: searchTimeMs,
      ));
    }
  }

  /// Очистка маппингов для завершённого/отменённого запроса
  void _cleanupRequest(int serviceId, int nativeId) {
    _serviceToNativeId.remove(serviceId);
    _nativeToServiceId.remove(nativeId);
  }

  /// Полная очистка ресурсов сервиса
  void dispose() {
    _log.info('Disposing SearchService...');
    
    // 1. Отменяем все активные нативные поиски
    final activeRequests = Map.from(_serviceToNativeId);
    activeRequests.forEach((serviceId, nativeId) {
      _ffi?.cancel(nativeId);
      _log.info('Force cancelled active search #$serviceId');
    });
    _serviceToNativeId.clear();
    _nativeToServiceId.clear();

    // 2. Закрываем стримы
    if (!_resultController.isClosed) _resultController.close();
    if (!_completionController.isClosed) _completionController.close();

    // 3. Освобождаем FFI-ресурсы
    _ffi?.dispose();
    _ffi = null;
    _isInitialized = false;
  }
}