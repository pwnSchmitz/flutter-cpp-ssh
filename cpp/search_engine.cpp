#include "search_engine.h"
#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <mutex>
#include <atomic>
#include <thread>
#include <memory>
#include <algorithm>
#define NOMINMAX
#include <windows.h>

// ─────────────────────────────────────────────
// 🔐 УПРАВЛЕНИЕ ЗАПРОСАМИ (ПОТОКОБЕЗОПАСНО)
// ─────────────────────────────────────────────
struct SearchRequest {
    int id;
    SearchResultCallback callback;
    std::atomic<bool> cancelled{false};
    std::string target; // UTF-8
};

using RequestPtr = std::shared_ptr<SearchRequest>;

static std::map<int, RequestPtr> g_active_requests;
static std::mutex g_requests_mutex;
static std::atomic<int> g_next_id{1};

// ─────────────────────────────────────────────
// 🌐 КОНВЕРТАЦИЯ КОДИРОВОК (Windows/CP1251)
// ─────────────────────────────────────────────
static std::string wstring_to_utf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string str(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size_needed, nullptr, nullptr);
    return str;
}

static std::string cp1251_to_utf8(const std::string& cp1251_str) {
    if (cp1251_str.empty()) return "";
    int size_w = MultiByteToWideChar(1251, 0, cp1251_str.c_str(), -1, nullptr, 0);
    if (size_w == 0) return cp1251_str;
    
    std::wstring wstr(size_w, 0);
    MultiByteToWideChar(1251, 0, cp1251_str.c_str(), -1, &wstr[0], size_w);
    
    int size_u8 = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string utf8_str(size_u8, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &utf8_str[0], size_u8, nullptr, nullptr);
    return utf8_str;
}

// ─────────────────────────────────────────────
// 🔍 ЯДРО ПОИСКА
// ─────────────────────────────────────────────
void search_in_file(SearchRequest* req, const std::wstring& filepath_w) {
    HANDLE hFile = CreateFileW(
        filepath_w.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, NULL
    );

    if (hFile == INVALID_HANDLE_VALUE) {
        std::cerr << "[Search] Failed to open file (ID: " << req->id << ")\n";
        return;
    }

    const size_t BUF_SIZE = 10 * 1024 * 1024; // 10MB чанк
    std::vector<char> buf(BUF_SIZE);
    std::string leftover;
    int line_number = 1;

    while (true) {
        // ⚡ Проверка флага отмены на каждой итерации чтения
        if (req->cancelled.load()) {
            std::cerr << "[Search] Cancelled request " << req->id << "\n";
            break;
        }

        DWORD bytesRead = 0;
        if (!ReadFile(hFile, buf.data(), BUF_SIZE, &bytesRead, NULL) || bytesRead == 0) break;

        std::string data = leftover + std::string(buf.data(), bytesRead);
        leftover.clear();

        size_t start = 0;
        size_t end = 0;
        
        while ((end = data.find('\n', start)) != std::string::npos) {
            std::string line = data.substr(start, end - start);
            if (!line.empty() && line.back() == '\r') line.pop_back();

            // Конвертация из CP1251 в UTF-8 для поиска
            std::string line_utf8 = cp1251_to_utf8(line);
            
            if (line_utf8.find(req->target) != std::string::npos) {
                if (req->callback) {
                    req->callback(req->id, 1, wstring_to_utf8(filepath_w).c_str(), line_utf8.c_str(), line_number, 0.0);
                }
            }

            line_number++;
            start = end + 1;
        }

        if (start < data.length()) {
            leftover = data.substr(start);
        }
    }

    CloseHandle(hFile);
}

// ─────────────────────────────────────────────
// 📤 ЭКСПОРТИРУЕМЫЕ ФУНКЦИИ (C-ABI)
// ─────────────────────────────────────────────
SEARCH_ENGINE_EXPORT void search_init() {
    std::lock_guard<std::mutex> lock(g_requests_mutex);
    for (auto& pair : g_active_requests) pair.second->cancelled.store(true);
    g_active_requests.clear();
    g_next_id.store(1);
}

SEARCH_ENGINE_EXPORT int search_start(
    const char** filepaths,
    int file_count,
    const char* target_number,
    SearchResultCallback callback) {

    if (!filepaths || file_count <= 0 || !target_number || !callback) {
        std::cerr << "[Search] Invalid arguments for search_start\n";
        return -1;
    }

    int id = g_next_id.fetch_add(1);
    auto req = std::make_shared<SearchRequest>();
    req->id = id;
    req->callback = callback;
    req->target = target_number; // UTF-8

    // Регистрируем запрос до запуска потока
    {
        std::lock_guard<std::mutex> lock(g_requests_mutex);
        g_active_requests[id] = req;
    }

    // Копируем пути в std::vector, так как память управляется Dart-стороной
    std::vector<std::string> paths;
    paths.reserve(file_count);
    for (int i = 0; i < file_count; ++i) paths.emplace_back(filepaths[i]);

    // 🚀 Запускаем фоновый поток. Функция возвращает ID мгновенно.
    std::thread([req, paths]() {
        for (const auto& path : paths) {
            if (req->cancelled.load()) break;

            int size = MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
            std::wstring wpath(size, 0);
            MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, &wpath[0], size);

            search_in_file(req.get(), wpath);
        }
        
        // Удаляем из карты активных запросов после завершения
        std::lock_guard<std::mutex> lock(g_requests_mutex);
        g_active_requests.erase(req->id);
    }).detach();

    return id;
}

SEARCH_ENGINE_EXPORT void search_cancel(int request_id) {
    std::lock_guard<std::mutex> lock(g_requests_mutex);
    auto it = g_active_requests.find(request_id);
    if (it != g_active_requests.end()) {
        it->second->cancelled.store(true);
    }
}

SEARCH_ENGINE_EXPORT void search_cleanup() {
    std::lock_guard<std::mutex> lock(g_requests_mutex);
    for (auto& pair : g_active_requests) pair.second->cancelled.store(true);
    g_active_requests.clear();
    g_next_id.store(1);
}