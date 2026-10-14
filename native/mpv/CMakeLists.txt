add_library(immivio_mpv_headers INTERFACE)
add_library(Immivio::MpvHeaders ALIAS immivio_mpv_headers)
target_include_directories(immivio_mpv_headers
                           INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_features(immivio_mpv_headers INTERFACE cxx_std_17)

# The bridge depends on Android/JNI; the headers above do not.
if(NOT ANDROID)
  return()
endif()

set(MPV_LIB_DIR
    "${CMAKE_CURRENT_LIST_DIR}/../../android/player-plugin/src/main/jniLibs/arm64-v8a"
)
if(NOT EXISTS "${MPV_LIB_DIR}/libmpv.so")
  message(
    FATAL_ERROR
      "Run configs/android_workflow.py configure to stage the locked mpv libraries"
  )
endif()
add_library(mpv_candidate SHARED IMPORTED)
set_target_properties(mpv_candidate PROPERTIES IMPORTED_LOCATION
                                               "${MPV_LIB_DIR}/libmpv.so")
add_library(avcodec_candidate SHARED IMPORTED)
set_target_properties(
  avcodec_candidate PROPERTIES IMPORTED_LOCATION "${MPV_LIB_DIR}/libavcodec.so")
add_library(quest_mpv SHARED src/mpv_core_probe.cpp src/mpv_gpu_probe.cpp
                             src/mpv_source.cpp)
target_compile_features(quest_mpv PRIVATE cxx_std_17)
target_compile_definitions(
  quest_mpv PRIVATE QUEST_STANDARD_MPV=$<BOOL:${QUEST_STANDARD_MPV}>)
target_compile_options(quest_mpv PRIVATE -Wall -Wextra -Werror)
target_link_libraries(
  quest_mpv
  PRIVATE mpv_candidate
          Immivio::MpvHeaders
          avcodec_candidate
          log
          android
          EGL
          GLESv3
          dl
          nativewindow
          mediandk)
target_link_options(quest_mpv PRIVATE "-Wl,-z,max-page-size=16384")
