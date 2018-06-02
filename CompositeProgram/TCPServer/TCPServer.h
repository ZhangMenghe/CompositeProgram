#pragma once

#define DEFAULT_PORT "9988"

#include <stdio.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iostream>
#include <thread>
#include <vector>
#pragma comment(lib,"ws2_32.lib") //Winsock Library
#define TCPSIZE 409600000
class Pipehandler;

class TCPServer {
public:
  WSADATA wsaData;
  int iResult;

  SOCKET ListenSocket = INVALID_SOCKET;
  SOCKET ClientSocket = INVALID_SOCKET;
  SOCKADDR_IN ClientInfo = { 0 };
  std::vector<Pipehandler*> seqhandlers;
  std::vector<Pipehandler*> parhandlers;

  struct addrinfo *result = NULL;
  struct addrinfo hints;

  int iSendResult;
  char recvbuf[TCPSIZE];
  int recvbuflen = TCPSIZE;
  bool flag = true;
  bool keepAlive = true;

  TCPServer();

  bool acceptClient();

  void update();

  ~TCPServer();
};

