/*-----------------------------------------------------------------------------
| Copyright (c) 2013-2026, Nucleic Development Team.
|
| Distributed under the terms of the Modified BSD License.
|
| The full license is in the file LICENSE, distributed with this software.
|----------------------------------------------------------------------------*/
#pragma once
#include "platform.h"

namespace kiwi
{

namespace impl
{

KIWI_ALWAYS_INLINE
inline bool nearZero(double value)
{
    return __builtin_fabs(value) < 1.0e-8;
}

} // namespace impl

} // namespace kiwi
