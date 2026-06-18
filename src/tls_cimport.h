#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#endif
#include <openssl/ssl.h>
#include <openssl/err.h>
