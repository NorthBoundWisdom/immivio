add_library(quest_media SHARED src/media_delete.cpp)
target_compile_features(quest_media PRIVATE cxx_std_17)
target_compile_options(quest_media PRIVATE -Wall -Wextra -Werror)
target_link_options(quest_media PRIVATE "-Wl,-z,max-page-size=16384")
