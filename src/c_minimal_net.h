// Truly minimal network declarations for Windows cross-compilation
// Declares only the exact functions used by tls.zig, no broad headers
// This avoids ALL MinGW fortify/Annex K translation errors.

#ifdef _WIN32
// Just the types we need
typedef unsigned int u32;
typedef unsigned char u8;
typedef unsigned short u16;
typedef int socklen_t;
typedef unsigned long long u64;

struct sockaddr { u16 sa_family; u8 sa_data[14]; };
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; u8 sin_zero[8]; };
struct addrinfo { int ai_flags; int ai_family; int ai_socktype; int ai_protocol; socklen_t ai_addrlen; struct sockaddr *ai_addr; char *ai_canonname; struct addrinfo *ai_next; };

#define AF_UNSPEC 0
#define AF_INET 2
#define SOCK_STREAM 1
#define SOL_SOCKET 1

int getaddrinfo(const char *node, const char *service, const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
int socket(int domain, int type, int protocol);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int close(int fd);

// time.h
struct timespec { long tv_sec; long tv_nsec; };
int nanosleep(const struct timespec *req, struct timespec *rem);

#else
// POSIX: standard headers work fine
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <time.h>
#endif
