// Truly minimal network declarations for Windows cross-compilation
// Declares only the exact types used by tls.zig, no includes at all.
// This avoids dependency on winsock2.h / MinGW headers entirely.
//
// For MSVC target (x86_64-windows-msvc), Zig bundles NO Windows SDK,
// so we cannot include any Windows headers.

#ifndef _WINDOWS_NET_MINIMAL_H
#define _WINDOWS_NET_MINIMAL_H

#ifdef _WIN32

typedef unsigned int u32;
typedef unsigned char u8;
typedef unsigned short u16;
typedef int socklen_t;
typedef u32 INT_PTR;

struct sockaddr { u16 sa_family; u8 sa_data[14]; };
struct sockaddr_in { u16 sin_family; u16 sin_port; u32 sin_addr; u8 sin_zero[8]; };
struct addrinfo {
    int ai_flags; int ai_family; int ai_socktype; int ai_protocol;
    socklen_t ai_addrlen; char *ai_canonname;
    struct sockaddr *ai_addr; struct addrinfo *ai_next;
};

// Extern declarations for the functions used by tls.zig.
// These are never CALLED on Windows (sendRaw returns error immediately),
// but the compiler needs the prototypes for type-checking.
int getaddrinfo(const char *node, const char *service,
    const struct addrinfo *hints, struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
int socket(int domain, int type, int protocol);
int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
int close(int fd);

// time.h types for nanosleep
struct timespec { long tv_sec; long tv_nsec; };
int nanosleep(const struct timespec *req, struct timespec *rem);

#else
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <time.h>
#endif

#endif
