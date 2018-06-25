#include "stdafx.h"
#include "TCPServer.h"
#include "Pipehandler.h"
#include "Encoder.h"

extern Encoder* encoder;
extern void Entrance(std::string rawString, std::string &resString);

TCPServer::TCPServer()
{
  // Initialize Winsock
  iResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
  if (iResult != 0)
  {
    printf("WSAStartup failed with error: %d\n", iResult);
    flag = false;
  }

  ZeroMemory(&hints, sizeof(hints));
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  hints.ai_flags = AI_PASSIVE;

  // Resolve the server address and port
  iResult = getaddrinfo(NULL, DEFAULT_PORT, &hints, &result);
  if (iResult != 0)
  {
    printf("getaddrinfo failed with error: %d\n", iResult);
    WSACleanup();
    flag = false;
  }
}

bool TCPServer::acceptClient()
{
  // Accept a client socket

  // Create a SOCKET for connecting to server
  ListenSocket = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
  if (ListenSocket == INVALID_SOCKET)
  {
    printf("socket failed with error: %ld\n", WSAGetLastError());
    freeaddrinfo(result);
    WSACleanup();
    flag = false;
  }

  // Setup the TCP listening socket
  iResult = bind(ListenSocket, result->ai_addr, (int)result->ai_addrlen);
  if (iResult == SOCKET_ERROR)
  {
    printf("bind failed with error: %d\n", WSAGetLastError());
    freeaddrinfo(result);
    closesocket(ListenSocket);
    WSACleanup();
    flag = false;
  }

  //freeaddrinfo(result);

  iResult = listen(ListenSocket, SOMAXCONN);
  if (iResult == SOCKET_ERROR)
  {
    printf("listen failed with error: %d\n", WSAGetLastError());
    closesocket(ListenSocket);
    WSACleanup();
    flag = false;
  }

  int addrsize = sizeof(ClientInfo);
  memset(&ClientInfo, 0, addrsize);
  ClientSocket = accept(ListenSocket, (struct sockaddr*)&ClientInfo, &addrsize);
  if (ClientSocket == INVALID_SOCKET)
  {
    printf("accept failed with error: %d\n", WSAGetLastError());
    closesocket(ListenSocket);
    WSACleanup();
    flag = false;
    puts("Bind done");
    return false;
  }

  //closesocket(ListenSocket);

  return true;
}

void TCPServer::update()
{
  //
	std::string gResString;
	Entrance("4", gResString);
  do
  {
    bool res = acceptClient();
    printf("accepted\n");
    do
    {
      printf("Waiting for data...\n");
      fflush(stdout);

      //clear the buffer by filling null, it might have previously received data
      memset(recvbuf, '\0', 40960000);

      iResult = recv(ClientSocket, recvbuf, recvbuflen, 0);
      if (iResult > 0)
      {
        std::vector<byte>* totalBuf = new std::vector<byte>();
        printf("Bytes received: %d\n", iResult);
        printf("Received packet from %s:%d\n", inet_ntoa(ClientInfo.sin_addr), ntohs(ClientInfo.sin_port));
        //printf("Data: %s\n", recvbuf);

        if (!strcmp(recvbuf, "end\n"))
        {
          printf("triggered\n");
          //break;
        }
        void* output = 0;
		int width, height;
		Encoder::MESSAGETYPE messagetype;
		Encoder::DATATYPE dataType;
		bool decode_result = encoder->decode((byte*)recvbuf, iResult, &output,
											  &width, &height, &messagetype, &dataType);
        //auto [decode_result, width, height, messagetype, dataType] = encoder->decode((byte*)recvbuf, iResult, &output);

		/*Encoder::MESSAGETYPE messagetype = Encoder::STRING;
		int width = 4;
		int height = 1;
		bool decode_result = true;
		Encoder::DATATYPE dataType = Encoder::DATATYPE::BYTE;
		output = (byte*)calloc(width, 1);

		memcpy(output, (byte*)recvbuf + 12, width);*/

		if (messagetype == Encoder::STRING) {
			std::string s((char *)output);
			//Entrance(s.substr(0, width), &gResTransAndRot);
			printf("string get: %s\n", s.substr(0, width));
		}
        if(messagetype == Encoder::RGB_R)
        {
          auto file = fopen("rgb.txt", "wb");
          fwrite(output, 1, width*height, file);
        }

        if (messagetype == Encoder::INTRINSIC)
        {
          printf("Message type: Intrinsic Matrix\n (width, height):(%d, %d);\n", width, height);

          if (decode_result) {
            printf("Data: \n");
            for (int i = 0; i < 4; i++)
            {
              for (int j = 0; j < 4; j++) {
                float entry = ((float *)output)[i * 4 + j];

                printf("%f ", entry);
              }
              printf("\n");
            }
            printf("\nMatrix end\n");
          }
        }

        if (messagetype == Encoder::EXTRINSIC)
        {
          printf("Message type: Extrinsic Matrix\n (width, height):(%d, %d);\n", width, height);
          if (decode_result) {
            printf("Data: \n");
            for (int i = 0; i < 4; i++)
            {
              for (int j = 0; j < 4; j++) {
                float entry = ((float *)output)[i * 4 + j];

                printf("%f ", entry);
              }
              printf("\n");
            }
            printf("\nMatrix end\n");
          }
        }

        if (messagetype == Encoder::INFRARED)
        {
          printf("Message type: Infrared image\n (width, height):(%d, %d);\n", width, height);
          if (decode_result) {
            printf("Data: \n");
            int min = 999;
            int max = 0;
            int min_i = -1;
            int max_i = -1;
            for (int i = 0; i < width * height; i++)
            {
              byte pixel = ((byte*)output)[i];
              if (pixel > max)
              {
                max = pixel;
                max_i = i;
              }
              if (pixel < min)
              {
                min = pixel;
                min_i = i;
              }
            }
            printf("min at %d: %d; max at %d: %d;\n", min_i, min, max_i, max);
            printf("Image end\n");
          }
        }

        if (messagetype == Encoder::DEPTH)
        {
          printf("Message type: Depth image\n (width, height):(%d, %d);\n", width, height);
          if (decode_result) {
            printf("Data: \n");
            int min = 999;
            int max = 0;
            int min_i = -1;
            int max_i = -1;
            for (int i = 0; i < width * height; i++)
            {
              byte pixel = ((byte*)output)[i];
              if (pixel > max)
              {
                max = pixel;
                max_i = i;
              }
              if (pixel < min)
              {
                min = pixel;
                min_i = i;
              }
            }
            printf("min at %d: %d; max at %d: %d;\n", min_i, min, max_i, max);
            printf("Image end\n");
          }
        }
		//TODO:SEND BACK RESULTS gResTransAndRot
        const char* backBuf = "Data Processed";

        if (seqhandlers.size() > 0)
        {
           byte* data = seqhandlers[0]->exchange((byte*)recvbuf, iResult);
        }

        iSendResult = send(ClientSocket, backBuf, strlen(backBuf) + 1, 0);
        if (iSendResult == SOCKET_ERROR)
        {
          printf("send failed with error: %d\n", WSAGetLastError());
          closesocket(ClientSocket);
          WSACleanup();
          flag = false;
        }
        printf("Bytes sent: %d\n", iSendResult);

        continue;

        if (seqhandlers.size() > 0)
        {
          byte* data = seqhandlers[0]->exchange((byte*)recvbuf, iResult);
        }

        for (int i = 0; i < parhandlers.size(); i++)
        {
          byte* data = parhandlers[i]->exchange((byte*)recvbuf, iResult);
        }

        // Echo the buffer back to the sender
        iSendResult = send(ClientSocket, recvbuf, iResult, 0);
        if (iSendResult == SOCKET_ERROR)
        {
          printf("send failed with error: %d\n", WSAGetLastError());
          closesocket(ClientSocket);
          WSACleanup();
          flag = false;
        }
        printf("Bytes sent: %d\n", iSendResult);
      }
      else if (iResult == 0)
        printf("Connection closing...\n");
      else
      {
        printf("recv failed with error: %d\n", WSAGetLastError());
        closesocket(ClientSocket);
        WSACleanup();
        flag = false;
      }
    }
    while (iResult > 0);
  }
  while (keepAlive);
}

TCPServer::~TCPServer()
{
  // shutdown the connection since we're done
  iResult = shutdown(ClientSocket, SD_SEND);
  if (iResult == SOCKET_ERROR)
  {
    printf("shutdown failed with error: %d\n", WSAGetLastError());
    closesocket(ClientSocket);
    WSACleanup();
  }

  // cleanup
  closesocket(ClientSocket);
  WSACleanup();
}
