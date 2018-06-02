#pragma once

#include <stdio.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iostream>
#include <thread>

#define MAXDATASIZE 409600000
#define PIPESIZE 409600000

class Pipehandler {
public:
  // open pipe
  HANDLE hPipe = NULL;
  LPSTR lpvMessage = const_cast<LPSTR>("Default message from client.");
  CHAR  chBuf[PIPESIZE];
  byte * lastData;
  BOOL   fSuccess = FALSE;
  DWORD  cbRead, cbToWrite, cbWritten, dwMode;
  LPSTR lpszPipename;
  bool flag = true;

  Pipehandler(std::string pipename, std::string szCmd);

  byte* exchange(byte* buf, int size);

  ~Pipehandler();
};
