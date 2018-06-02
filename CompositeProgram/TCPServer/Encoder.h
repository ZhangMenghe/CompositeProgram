#pragma once
#include <tuple>
#include <Windows.h>

class Encoder
{
public:

  int MessageWidthIndex = 0; // 4 byte for message width
  int MessageHeightIndex = 4; // 4 byte for message height
  int MessageTypeIndex = 8; // one byte for message type
  int DataTypeIndex = 9; // one byte for data type
  int Padding = 10; // 2 byte reserved - or extra info
  int DataStartPosition = 12; // 

  int HeaderSize = 12; // 12 byte in total

  enum MESSAGETYPE
  {
    INTRINSIC = 0,
    EXTRINSIC,
    INFRARED,
    DEPTH,
    RGB_R,
    RGB_G,
    RGB_B,
	STRING,
    UNKMESSAGE
  };

  enum DATATYPE
  {
    BYTE = 0,
    INT,
    FLOAT,
    UNKDATA
  };

  Encoder();

  bool encode(byte* img, int width, int height, MESSAGETYPE messagetype, byte* output);

  bool encode(float* mat, MESSAGETYPE messagetype, byte* output);

  std::tuple<bool, int, int, MESSAGETYPE, DATATYPE> decode(const byte* input, const int recvlen, void** output);
  
  bool decode(const byte* input, const int recvlen, void** output, int * width, int *height, MESSAGETYPE * messagetype, DATATYPE * dataType);

  void decodeImage(byte* input, byte* output, int size);

  void decodeMat4(byte* input, float* output, int size);
};
