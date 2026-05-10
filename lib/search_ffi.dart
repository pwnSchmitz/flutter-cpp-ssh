import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ─────────────────────────────────────────────
// 📜 ТИПЫ И СИГНАТУРЫ
// ─────────────────────────────────────────────

typedef SearchResultCallbackNative = Void Function(
  Int32 requestId,
  Uint8 found,
  Pointer<Char> filename,
  Pointer<Char> linePreview,
  Int32 lineNumber,
  Double searchTimeMs,
);

typedef SearchResultCallbackDart = void Function(
  int requestId,
  bool found,
  String filename,
  String linePreview,
  int lineNumber,
  double searchTimeMs,
);

typedef SearchInitNative = Void Function();
typedef SearchStartNative = Int32 Function(
  Pointer<Pointer<Char>> filepaths,
  Int32 fileCount,
  Pointer<Char> targetNumber,
  Pointer<NativeFunction<SearchResultCallbackNative>> callback,
);
typedef SearchCancelNative = Void Function(Int32 requestId);
typedef SearchCleanupNative = Void Function();

// ─────────────────────────────────────────────
// 🛠️ FFI WRAPPER
// ─────────────────────────────────────────────

class SearchEngineFFI {
  late final DynamicLibrary _lib;
  late final NativeCallable<SearchResultCallbackNative> _callbackHandle;
  final SearchResultCallbackDart _dartCallback;

  late final void Function() _nativeInit;
  late final int Function(Pointer<Pointer<Char>>, int, Pointer<Char>, Pointer<NativeFunction<SearchResultCallbackNative>>) _nativeStart;
  late final void Function(int) _nativeCancel;
  late final void Function() _nativeCleanup;
  
  bool _isDisposed = false;

  SearchEngineFFI._(this._dartCallback) {
    _loadLibrary();
    _bindFunctions();
    _setupCallback();
  }

  static Future<SearchEngineFFI?> create({required SearchResultCallbackDart callback}) async {
    // 🐧 Проверка платформы: поиск работает только на Windows
    if (!Platform.isWindows) {
      print('[SearchEngineFFI] ⚠️ Search is only supported on Windows. Running on ${Platform.operatingSystem}.');
      return null; // Возвращаем null вместо исключения — приложение не упадёт
    }
    try {
      return SearchEngineFFI._(callback);
    } catch (e) {
      print('[SearchEngineFFI] ❌ Failed to initialize: $e');
      return null;
    }
  }

  void _loadLibrary() {
    try {
      _lib = DynamicLibrary.open('search_engine.dll');
    } catch (e) {
      throw Exception(
        'Failed to load search_engine.dll: $e\n'
        'Убедитесь, что файл находится рядом с исполняемым файлом или в PATH.',
      );
    }
  }

  void _bindFunctions() {
    try {
      _nativeInit = _lib.lookupFunction<SearchInitNative, void Function()>('search_init');
      _nativeStart = _lib.lookupFunction<SearchStartNative, int Function(
        Pointer<Pointer<Char>>, int, Pointer<Char>, Pointer<NativeFunction<SearchResultCallbackNative>>
      )>('search_start');
      _nativeCancel = _lib.lookupFunction<SearchCancelNative, void Function(int)>('search_cancel');
      _nativeCleanup = _lib.lookupFunction<SearchCleanupNative, void Function()>('search_cleanup');
    } catch (e) {
      throw Exception('FFI binding error: $e. Проверьте имена функций в search_engine.h');
    }
  }

  void _setupCallback() {
    // ✅ Исправлено: убран exceptionalReturn, добавлен try-catch внутри
    _callbackHandle = NativeCallable<SearchResultCallbackNative>.listener(
      (requestId, found, filename, linePreview, lineNumber, searchTimeMs) {
        try {
          final filenameStr = filename.cast<Utf8>().toDartString();
          final previewStr = linePreview.cast<Utf8>().toDartString();
          
          // Future.microtask гарантирует выполнение в главном event loop
          Future.microtask(() {
            if (!_isDisposed) {
              _dartCallback(requestId, found != 0, filenameStr, previewStr, lineNumber, searchTimeMs);
            }
          });
        } catch (e) {
          print('[SearchEngineFFI] Callback error: $e');
        }
      },
      // ✅ exceptionalReturn удалён — это устаревший параметр
    );
  }

  void init() {
    if (_isDisposed) return;
    _nativeInit();
  }

  int start(List<String> filepaths, String targetNumber) {
    if (_isDisposed) return -1;
    if (filepaths.isEmpty) throw ArgumentError('File paths cannot be empty');

    return using<int>((arena) {
      final filePathsPtr = arena<Pointer<Char>>(filepaths.length);
      for (int i = 0; i < filepaths.length; i++) {
        filePathsPtr[i] = filepaths[i].toNativeUtf8(allocator: arena).cast<Char>();
      }
      final targetPtr = targetNumber.toNativeUtf8(allocator: arena).cast<Char>();

      return _nativeStart(
        filePathsPtr,
        filepaths.length,
        targetPtr,
        _callbackHandle.nativeFunction,
      );
    });
  }

  void cancel(int requestId) {
    if (!_isDisposed) _nativeCancel(requestId);
  }

  void cleanup() {
    if (!_isDisposed) _nativeCleanup();
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    try {
      _callbackHandle.close(); // ✅ Освобождаем нативный ресурс
      cleanup();
    } catch (e) {
      print('[SearchEngineFFI] Dispose error: $e');
    }
  }
}