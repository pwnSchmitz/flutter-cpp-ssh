#pragma once

// ─────────────────────────────────────────────
// 🌍 ПЛАТФОРМЕННЫЙ ЭКСПОРТ СИМВОЛОВ
// ─────────────────────────────────────────────
#ifdef _WIN32
    #define SEARCH_ENGINE_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) && __GNUC__ >= 4
    #define SEARCH_ENGINE_EXPORT __attribute__((visibility("default")))
#else
    #define SEARCH_ENGINE_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @typedef SearchResultCallback
 * Callback для передачи результатов поиска обратно в Dart.
 * ⚠️ ВЫЗЫВАЕТСЯ ИЗ НАТИВНОГО ПОТОКА! Убедитесь, что обработчик на Dart-стороне 
 * корректно переключается в главный изолят (Future.microtask / IsolateNameScope).
 *
 * @param request_id Уникальный ID запроса поиска
 * @param found 1 если найдено совпадение, 0 если нет
 * @param filename Путь к файлу (UTF-8, null-terminated строка)
 * @param line_preview Текст строки с совпадением (UTF-8, null-terminated строка)
 * @param line_number Номер строки в файле (начиная с 1)
 * @param search_time_ms Время выполнения поиска в мс (опционально, пока 0.0)
 */
typedef void (*SearchResultCallback)(
    int request_id,
    int found,
    const char* filename,
    const char* line_preview,
    int line_number,
    double search_time_ms
);

/**
 * Инициализация поискового движка.
 * Должна вызываться один раз перед первым поиском.
 */
SEARCH_ENGINE_EXPORT void search_init(void);

/**
 * Запуск асинхронного поиска в указанных файлах.
 * Функция возвращает управление сразу, поиск выполняется в фоне.
 *
 * @param filepaths Массив указателей на строки с путями к файлам (UTF-8)
 * @param file_count Количество файлов в массиве
 * @param target_number Искомая строка/номер (UTF-8)
 * @param callback Функция обратного вызова для получения результатов
 * @return request_id Уникальный идентификатор запроса для отслеживания/отмены
 */
SEARCH_ENGINE_EXPORT int search_start(
    const char** filepaths,
    int file_count,
    const char* target_number,
    SearchResultCallback callback
);

/**
 * Отмена активного поиска по request_id.
 * Флаг отмены будет проверен в следующем цикле чтения файла.
 *
 * @param request_id ID запроса, возвращённый search_start
 */
SEARCH_ENGINE_EXPORT void search_cancel(int request_id);

/**
 * Очистка ресурсов поискового движка.
 * Сбрасывает глобальный callback и внутренние состояния.
 * Вызывать перед выгрузкой библиотеки или завершением работы приложения.
 */
SEARCH_ENGINE_EXPORT void search_cleanup(void);

#ifdef __cplusplus
}
#endif