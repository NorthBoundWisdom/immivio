cmake_minimum_required(VERSION 3.22)
project(Immivio LANGUAGES C CXX)

# Reusable, platform-independent headers also belong to the host test graph.
add_subdirectory(mpv)

if(ANDROID)
  add_subdirectory(media)
  add_subdirectory(render-bridge)
else()
  include(CTest)
  if(BUILD_TESTING)
    add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../tests/native"
                     "${CMAKE_CURRENT_BINARY_DIR}/tests")
  endif()
endif()
