#include "stdafx.h"
#include "Pipehandler.h"

Pipehandler::Pipehandler(std::string pipename, std::string szCmd) {
  // Try to open a named pipe; wait for it, if necessary. 
  //"\\\\.\\pipe\\testpipe"
  lastData = (byte *)calloc(MAXDATASIZE, sizeof(byte));
  lpszPipename = const_cast<LPSTR>(pipename.c_str());
  bool opened = false;
  while (!opened) {
    hPipe = CreateFileA(
      lpszPipename, // pipe name 
      GENERIC_READ | // read and write access 
      GENERIC_WRITE,
      FILE_SHARE_DELETE| FILE_SHARE_READ | FILE_SHARE_WRITE, // no sharing 
      NULL, // default security attributes
      OPEN_EXISTING, // opens existing pipe 
      0, // default attributes 
      NULL); // no template file 

    // Break if the pipe handle is valid. 

    if (hPipe != INVALID_HANDLE_VALUE)
      break;

    printf("Could not open pipe. GLE=%d\n", GetLastError());

    // Exit if an error other than ERROR_PIPE_BUSY occurs. 

    //if (GetLastError() != ERROR_PIPE_BUSY)
    //{
    //  printf("Could not open pipe. GLE=%d\n", GetLastError());
    //  return -1;
    //}
    //
    //// All pipe instances are busy, so wait for 20 seconds. 
    //
    //if (!WaitNamedPipeA(lpszPipename, 20000))
    //{
    //  printf("Could not open pipe: 20 second wait timed out.");
    //  return -1;
    //}

    // Sleep for 50ms before create process
    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    GetStartupInfoA(&si);
    si.cb = sizeof(STARTUPINFO);
    si.wShowWindow = SW_SHOW;
    si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
    // "\"C:\\Users\\DESKTOP\\PycharmProjects\\untitled\\venv1\\Scripts\\python.exe\" C:\\Users\\DESKTOP\\PycharmProjects\\Pipehandler\\pipehandle.py";
    LPSTR szCmdLine = const_cast<LPSTR>(szCmd.c_str());
    if (!CreateProcessA(NULL, szCmdLine, NULL, NULL, TRUE, CREATE_NEW_CONSOLE, NULL, NULL, &si, &pi)) {
      printf(NULL, "can't create process", "error", MB_OK);
    }

    // Sleep for 5second before retrying to CreateFileA
    std::this_thread::sleep_for(std::chrono::seconds(5));
  }

  // The pipe connected; change to message-read mode. 

  dwMode = PIPE_READMODE_MESSAGE;
  fSuccess = SetNamedPipeHandleState(
    hPipe, // pipe handle 
    &dwMode, // new pipe mode 
    NULL, // don't set maximum bytes 
    NULL); // don't set maximum time 
  if (!fSuccess) {
    printf("SetNamedPipeHandleState failed. GLE=%d\n", GetLastError());
    //return -1;
    flag = false;
  }
}

byte* Pipehandler::exchange(byte* buf, int size) {
  // Send a message to the pipe server. 
  int i = 0;
  memset(lastData, 0, MAXDATASIZE);
  cbToWrite = size;
  printf("Sending %d byte message: \"%s\"\n", cbToWrite, buf);

  fSuccess = WriteFile(
    hPipe, // pipe handle 
    buf, // message 
    cbToWrite, // message length 
    &cbWritten, // bytes written 
    NULL); // not overlapped 

  if (!fSuccess) {
    printf("WriteFile to pipe failed. GLE=%d\n", GetLastError());
    //return -1;
    hPipe = CreateFileA(
      lpszPipename, // pipe name 
      GENERIC_READ | // read and write access 
      GENERIC_WRITE,
      FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE, // no sharing 
      NULL, // default security attributes
      OPEN_EXISTING, // opens existing pipe 
      0, // default attributes 
      NULL); // no template file 

             // Break if the pipe handle is valid. 

    printf("Could not open pipe. GLE=%d\n", GetLastError());
  }

  printf("\nMessage sent to server, receiving reply as follows:\n");

  do {
    // Read from the pipe. 

    fSuccess = ReadFile(
      hPipe, // pipe handle 
      chBuf, // buffer to receive reply 
      PIPESIZE, // size of buffer 
      &cbRead, // number of bytes read 
      NULL); // not overlapped 

    if (!fSuccess && GetLastError() != ERROR_MORE_DATA)
      break;

    printf("\"%s\"\n", chBuf);
    memcpy(lastData + i, chBuf, cbRead);
    i += cbRead;
  }
  while (!fSuccess); // repeat loop if ERROR_MORE_DATA 

  if (!fSuccess) {
    printf("ReadFile from pipe failed. GLE=%d\n", GetLastError());
    hPipe = CreateFileA(
      lpszPipename, // pipe name 
      GENERIC_READ | // read and write access 
      GENERIC_WRITE,
      FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE, // no sharing 
      NULL, // default security attributes
      OPEN_EXISTING, // opens existing pipe 
      0, // default attributes 
      NULL); // no template file 
    //return -1;
  }
  return lastData;
}

Pipehandler::~Pipehandler() {
  delete(lastData);
  CloseHandle(hPipe);
}
