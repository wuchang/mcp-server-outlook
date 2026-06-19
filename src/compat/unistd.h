#pragma once
#ifdef _WIN32
#include <io.h>
#include <process.h>
#else
#error "This header is only for Windows compat"
#endif
