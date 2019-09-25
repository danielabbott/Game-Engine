#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>

WSADATA wsaData;

int netInit() {
	int iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
	if (iResult != 0) {
		printf("WSAStartup failed with error: %d\n", iResult);
		return 1;
	}
	return 0;
}

void netDeinit() {
	WSACleanup();
}

// port is the port u16 integer as a null-terminated string
// returns 0 on success
int connectTCP(const char* address, unsigned short port, uintptr_t * socket_out)
{
	SOCKET ConnectSocket = INVALID_SOCKET;
	struct addrinfo* result = NULL,
		* ptr = NULL,
		hints;

	int iResult;

	ZeroMemory(&hints, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_protocol = IPPROTO_TCP;

	// Resolve the server address and port
	char portString[20];
	sprintf(portString, "%d", port);
	iResult = getaddrinfo(address, portString, &hints, &result);
	if (iResult != 0) {
		printf("getaddrinfo failed with error: %d\n", iResult);
		return 1;
	}

	// Attempt to connect to an address until one succeeds
	for (ptr = result; ptr != NULL; ptr = ptr->ai_next) {

		// Create a SOCKET for connecting to server
		ConnectSocket = socket(ptr->ai_family, ptr->ai_socktype,
			ptr->ai_protocol);
		if (ConnectSocket == INVALID_SOCKET) {
			printf("socket failed with error: %ld\n", WSAGetLastError());
			return 1;
		}

		// Connect to server.
		iResult = connect(ConnectSocket, ptr->ai_addr, (int)ptr->ai_addrlen);
		if (iResult == SOCKET_ERROR) {
			closesocket(ConnectSocket);
			ConnectSocket = INVALID_SOCKET;
			continue;
		}
		break;
	}

	freeaddrinfo(result);

	if (ConnectSocket == INVALID_SOCKET) {
		return 1;
	}
	*socket_out = ConnectSocket;
	return 0;
}

// Returns number of bytes read
int sendtcp(uintptr_t socket, void* buffer, int bufferLength) {
	int iResult;

	// Send an initial buffer
	iResult = send(socket, buffer, bufferLength, 0);
	if (iResult == SOCKET_ERROR) {
		printf("tcp send failed with error: %d\n", WSAGetLastError());
		return -1;
	}

	return iResult;
}

void disableTCPSend(uintptr_t socket) {
	shutdown(socket, SD_SEND);
}

void disableTCPRecieve(uintptr_t socket) {
	shutdown(socket, SD_RECEIVE);
}

void disableTCPSendAndReieve(uintptr_t socket) {
	shutdown(socket, SD_BOTH);
}

void closeTCPConnection(uintptr_t socket) {
	closesocket(socket);
}

int recvtcp(uintptr_t socket, void* recvBuf, int bytes) {
	int iResult = recv(socket, recvBuf, bytes, 0);
	return iResult;
}
