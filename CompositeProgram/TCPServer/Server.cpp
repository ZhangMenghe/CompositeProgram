// UDPServer.cpp: 定义控制台应用程序的入口点。
//

#include "stdafx.h"
#include <thread>
#include "Pipehandler.h"

#pragma comment(lib,"ws2_32.lib") //Winsock Library

#define PORT 9988   //The port on which to listen for incoming data

#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <stdlib.h>
#include "TCPServer.h"
#include <csignal>
#include "Encoder.h"

#define DEFAULT_PORT "9988"
TCPServer * server = 0;
Pipehandler * pypipe = 0;
static void shutdown(int signum)
{
  printf("got signal #%d, terminating\n", signum);
  // cleanup
  if(server) {
    delete(server);
  }
  if(pypipe) {
    delete(pypipe);
  }
  _exit(1);
}


Encoder * encoder;

int __cdecl main(int argc, char * argv[])
{


  signal(SIGINT, shutdown);
  signal(SIGTERM, shutdown);
  signal(SIGSEGV, shutdown);

  server = new TCPServer();


  printf("Finished Setting up server.\nStart opening pipe...\n");
  //std::string pyn("\\\\.\\pipe\\testpipe");
  //std::string pycmd("\"C:\\Program Files (x86)\\Microsoft Visual Studio\\Shared\\Python36_64\\python.exe\" \"C:\\Users\\Weichen Liu\\Documents\\GitHub\\TCPServer\\pipehandle.py");
  //pypipe = new Pipehandler(pyn, pycmd);

  server->seqhandlers.push_back(pypipe);

  encoder = new Encoder();
  
  server->update();

  



  return 0;
}





