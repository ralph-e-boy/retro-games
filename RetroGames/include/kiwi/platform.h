/*-----------------------------------------------------------------------------
| Copyright (c) 2013-2025, Nucleic Development Team.
|
| Distributed under the terms of the Modified BSD License.
|
| The full license is in the file LICENSE, distributed with this software.
|----------------------------------------------------------------------------*/
#pragma once
#include <cmath>
#include <cstdint>

// Force-inline for hot-path functions
#if defined(__GNUC__) || defined(__clang__)
#define KIWI_ALWAYS_INLINE __attribute__((always_inline))
#elif defined(_MSC_VER)
#define KIWI_ALWAYS_INLINE __forceinline
#else
#define KIWI_ALWAYS_INLINE
#endif

// Branch prediction hints
#if defined(__GNUC__) || defined(__clang__)
#define KIWI_LIKELY(x)   __builtin_expect(!!(x), 1)
#define KIWI_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
#define KIWI_LIKELY(x)   (x)
#define KIWI_UNLIKELY(x) (x)
#endif

// Accelerate framework availability
#if defined(__APPLE__) && __has_include(<Accelerate/Accelerate.h>)
#define KIWI_HAS_ACCELERATE 1
#include <Accelerate/Accelerate.h>
#else
#define KIWI_HAS_ACCELERATE 0
#endif
