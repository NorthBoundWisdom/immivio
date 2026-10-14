find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter)

foreach(name IN ITEMS mpv_json_oracle pgs_bitmap_checks seek_trace_test)
  add_executable(${name} ${name}.cpp)
  target_link_libraries(${name} PRIVATE Immivio::MpvHeaders)
  if(MSVC)
    target_compile_options(${name} PRIVATE /EHsc /W4 /WX /UNDEBUG)
  else()
    target_compile_options(${name} PRIVATE -Wall -Wextra -Werror -UNDEBUG)
  endif()
endforeach()

add_test(
  NAME mpv_json_round_trip
  COMMAND
    "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/verify_mpv_json.py"
    --executable "$<TARGET_FILE:mpv_json_oracle>" --output
    "${CMAKE_CURRENT_BINARY_DIR}/json-results")
add_test(NAME pgs_bitmap COMMAND pgs_bitmap_checks)
add_test(NAME seek_trace COMMAND seek_trace_test)
