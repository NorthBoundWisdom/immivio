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
add_library(quest_mpv SHARED mpv_core_probe.cpp mpv_gpu_probe.cpp
                             mpv_source.cpp)
target_compile_features(quest_mpv PRIVATE cxx_std_17)
target_compile_definitions(
  quest_mpv PRIVATE QUEST_STANDARD_MPV=$<BOOL:${QUEST_STANDARD_MPV}>)
target_include_directories(quest_mpv
                           PRIVATE "${CMAKE_CURRENT_LIST_DIR}/include")
target_compile_options(quest_mpv PRIVATE -Wall -Wextra -Werror)
target_link_libraries(
  quest_mpv
  PRIVATE mpv_candidate
          avcodec_candidate
          log
          android
          EGL
          GLESv3
          dl
          nativewindow
          mediandk)
target_link_options(quest_mpv PRIVATE "-Wl,-z,max-page-size=16384")
