#pragma once

// The Godot template owns the single packaged libc++_shared. NDK r30's LLVM 21
// headers otherwise emit std::__hash_memory calls absent from that older runtime.
// Select libc++'s own inline CityHash/Murmur fallback, rather than adding a second
// C++ runtime or supplying a replacement hash implementation. Apply this before
// any functional/string/unordered_map headers in MNN and the inference wrapper.
#if defined(__ANDROID__) && defined(__cplusplus) && __has_include(<__configuration/availability.h>)
#include <__config>
#include <__configuration/availability.h>
#if defined(_LIBCPP_AVAILABILITY_HAS_HASH_MEMORY)
#undef _LIBCPP_AVAILABILITY_HAS_HASH_MEMORY
#define _LIBCPP_AVAILABILITY_HAS_HASH_MEMORY 0
#endif
#endif
