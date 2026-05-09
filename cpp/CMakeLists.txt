cmake_minimum_required(VERSION 3.15)
project(search_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ❌ Убрали CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS
# Теперь используем явный макрос SEARCH_ENGINE_EXPORT из search_engine.h
# Это даёт полный контроль над экспортом и убирает лишние символы

add_library(search_engine SHARED
    search_engine.cpp
    search_engine.h
)

# Поддержка Unicode для корректной работы Windows API (CreateFileW, MultiByteToWideChar и т.д.)
target_compile_definitions(search_engine PRIVATE _UNICODE UNICODE)

# 📦 Автоматическая сборка DLL в директорию запуска Flutter после компиляции
if(WIN32)
    # Путь к папке Runner в сборке Windows
    set(RUNNER_DIR "${CMAKE_SOURCE_DIR}/../build/windows/x64/runner")
    
    add_custom_command(TARGET search_engine POST_BUILD
        # Создаём папки, если их ещё нет (первая сборка)
        COMMAND ${CMAKE_COMMAND} -E make_directory "${RUNNER_DIR}/Debug"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${RUNNER_DIR}/Release"
        # Копируем DLL, только если она изменилась (ускоряет повторные сборки)
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:search_engine>
            "${RUNNER_DIR}/Debug/$<TARGET_FILE_NAME:search_engine>"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            $<TARGET_FILE:search_engine>
            "${RUNNER_DIR}/Release/$<TARGET_FILE_NAME:search_engine>"
    )
endif()