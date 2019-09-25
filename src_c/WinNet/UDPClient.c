#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS
#define _WINSOCK_DEPRECATED_NO_WARNINGS

#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>



int createUDPClientSocket(const char* serverIP, uint16_t destinationPort, uint16_t localPort, uintptr_t* socket_) {
	SOCKET s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

	if (s == INVALID_SOCKET) {
		return 1;
	}

	struct sockaddr_in localAddr;

	localAddr.sin_family = AF_INET;
	localAddr.sin_port = htons(localPort);
	//localAddr.sin_addr.s_addr = inet_addr("127.0.0.1");
	if (inet_pton(AF_INET, "127.0.0.1", &localAddr.sin_addr.s_addr) != 1) {
		return 1;
	}

	if (bind(s, (SOCKADDR*)& localAddr, sizeof(localAddr)) == SOCKET_ERROR) {
		closesocket(s);
		return 1;
	}

	////

	struct sockaddr_in destAddr;

	destAddr.sin_family = AF_INET;
	destAddr.sin_port = htons(destinationPort);
	if (inet_pton(AF_INET, serverIP, &destAddr.sin_addr.s_addr) != 1) {
		return 1;
	}
	//destAddr.sin_addr.s_addr = inet_addr(serverIP);

	if (connect(s, (SOCKADDR*)& destAddr, sizeof(destAddr)) == SOCKET_ERROR) {
		closesocket(s);
		return 1;
	}


	*socket_ = s;
	return 0;
}

int udpClientRecv(uintptr_t s, void* buffer, int bytes) {
	return recv(s, buffer, bytes, 0);
}

int udpClientSend(uintptr_t s, const void* buffer, int bytes) {
	return send(s, buffer, bytes, 0);
}

void closeUDPClientSocket(uintptr_t s) {
	closesocket(s);
}
