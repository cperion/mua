# Package the existing BUI C implementation for LuaJIT; no Lua 5.4 binding.
# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.24)
project(mua_bui LANGUAGES C CXX)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_SYSTEM_NAME MATCHES "^(Linux|Windows)$")
  message(FATAL_ERROR "The mua_bui native bundle supports Linux and Windows")
endif()
if(WIN32 AND NOT MINGW)
  message(FATAL_ERROR "Windows builds use MinGW-w64; select its GCC toolchain and Ninja or MinGW Makefiles")
endif()
if(CMAKE_CROSSCOMPILING)
  message(FATAL_ERROR "Build and run the BUI ABI tests on the target; cross-compilation is not supported")
endif()

get_filename_component(MUA_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(BUI_SOURCE_DIR "${MUA_SOURCE_DIR}/../bui" CACHE PATH "BUI checkout with the pinned public headers")
file(REAL_PATH "${BUI_SOURCE_DIR}" BUI_SOURCE_DIR)
# Reconfigure on header changes as well as on changes to the lock itself.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/headers.lock" BUI_HEADER_LOCK)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/headers.lock")
foreach(entry IN LISTS BUI_HEADER_LOCK)
  if(NOT entry MATCHES "^([0-9a-f]+) (.+)$")
    message(FATAL_ERROR "Malformed BUI header lock entry: ${entry}")
  endif()
  set(expected "${CMAKE_MATCH_1}")
  set(header "${BUI_SOURCE_DIR}/${CMAKE_MATCH_2}")
  if(NOT EXISTS "${header}")
    message(FATAL_ERROR "Missing ${header}; set BUI_SOURCE_DIR to the BUI checkout")
  endif()
  # Git may check out CRLF on Windows; pin content, not checkout line endings.
  file(READ "${header}" header_text)
  string(REPLACE "\r\n" "\n" header_text "${header_text}")
  string(SHA256 actual "${header_text}")
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "${header} changed: review bui/cdef.lua and the ABI tests before updating headers.lock")
  endif()
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${header}")
endforeach()

# These unrelated bindings must not bring another Lua runtime into the process.
set(BUI_BUILD_LUA_BINDINGS OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_PYTHON_BINDINGS OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_QT_BACKEND OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_UI OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_IMGUI OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(BUI_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory("${BUI_SOURCE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/upstream" EXCLUDE_FROM_ALL)

add_library(mua_bui SHARED bridge.c)
target_link_libraries(mua_bui PRIVATE bui_kit bui_api)
# FFI looks symbols up by name; no C caller otherwise keeps every public object linked.
set_property(TARGET mua_bui PROPERTY LINK_LIBRARY_OVERRIDE "WHOLE_ARCHIVE,bui_kit,bui_gpu,bui_api")
if(WIN32)
  set_target_properties(mua_bui PROPERTIES PREFIX "")
  # Whole-archive retains the objects; PE also needs their names in the export table.
  target_link_options(mua_bui PRIVATE -Wl,--export-all-symbols -static-libgcc -static-libstdc++)
else()
  target_link_options(mua_bui PRIVATE -Wl,--no-undefined -Wl,-Bsymbolic)
endif()

include(CTest)
if(BUILD_TESTING)
  find_program(LUAJIT_EXECUTABLE NAMES luajit REQUIRED)
  add_executable(bui_abi_probe abi_probe.c)
  target_include_directories(bui_abi_probe PRIVATE "${BUI_SOURCE_DIR}/kit/include"
    "${BUI_SOURCE_DIR}/gpu/include" "${BUI_SOURCE_DIR}/api")
  # CTest owns the native process and its exit status; Lua reads data, not a shell pipe.
  set(abi_report "${CMAKE_CURRENT_BINARY_DIR}/abi-$<CONFIG>.tsv")
  add_test(NAME bui_abi COMMAND bui_abi_probe "${abi_report}")
  set_tests_properties(bui_abi PROPERTIES FIXTURES_SETUP bui_abi TIMEOUT 30)
  add_test(NAME bui_ffi COMMAND "${LUAJIT_EXECUTABLE}" "${MUA_SOURCE_DIR}/tests/bui.lua"
    "$<TARGET_FILE:mua_bui>" "${abi_report}")
  set_tests_properties(bui_ffi PROPERTIES FIXTURES_REQUIRED bui_abi
    WORKING_DIRECTORY "${MUA_SOURCE_DIR}" TIMEOUT 60)
  option(BUI_FFI_TEST_WINDOW "Also test a real native window (requires a desktop)" OFF)
  if(BUI_FFI_TEST_WINDOW)
    add_test(NAME bui_window COMMAND "${LUAJIT_EXECUTABLE}" "${MUA_SOURCE_DIR}/tests/bui.lua"
      "$<TARGET_FILE:mua_bui>" "${abi_report}" --window)
    set_tests_properties(bui_window PROPERTIES FIXTURES_REQUIRED bui_abi
      WORKING_DIRECTORY "${MUA_SOURCE_DIR}" TIMEOUT 30)
  endif()
endif()
