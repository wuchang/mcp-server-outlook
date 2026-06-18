// Minimal C declarations — avoids MinGW fortify/Annex K issues on Windows
// Used instead of broad <stdlib.h>/<stdio.h> includes
// On Windows, declare only the functions we use.

#ifdef _WIN32
#define __STDC_LIB_EXT1__ 0
#include <stddef.h> // for size_t
// On Windows, manually declare the functions we need
// to avoid including full headers with MinGW fortify issues
char *getenv(const char *name);
int mkdir(const char *pathname);
int remove(const char *pathname);
// stdio functions (declared without macros)
typedef struct _iobuf FILE;
extern FILE *__acrt_iob_func(int idx);
FILE *fopen(const char *path, const char *mode);
int fclose(FILE *f);
int fgetc(FILE *f);
size_t fwrite(const void *ptr, size_t sz, size_t n, FILE *f);
#else
// POSIX: standard headers work fine
#include <stdlib.h>
#include <stdio.h>
#include <sys/stat.h>
#endif
