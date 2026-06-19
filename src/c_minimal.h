// Absolute minimal C declarations for Windows cross-compilation.
// Declares ONLY the functions used by the project, with NO includes.
// This completely avoids MinGW header translation bugs (wcscat_s, etc.).

#ifndef _WIN32
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
#else
#define _WIN32_WINNT 0x0601
typedef unsigned long long size_t;
typedef long long time_t;

// stdlib functions
char *getenv(const char *name);
int remove(const char *pathname);

// stdio types and functions — forward declared opaque type
// We only pass FILE* pointers, never dereference them
struct __File { int _dummy; };
typedef struct __File FILE;
FILE *fopen(const char *path, const char *mode);
int fclose(FILE *f);
int fgetc(FILE *f);
size_t fwrite(const void *ptr, size_t sz, size_t n, FILE *f);

// sys/stat
int mkdir(const char *pathname);

// time.h types (needed by log.zig)
struct timespec { long tv_sec; long tv_nsec; };
time_t time(time_t *t);
int nanosleep(const struct timespec *req, struct timespec *rem);
#endif
