#include "stdafx.h"
#include "Encoder.h"

Encoder::Encoder()
{
}

bool Encoder::encode(byte* img, int width, int height, MESSAGETYPE messagetype, byte* output)
{
  memcpy(output + MessageWidthIndex, &width, 4);
  memcpy(output + MessageHeightIndex, &height, 4);
  byte mtype = messagetype;
  byte dtype = DATATYPE::BYTE;
  output[MessageTypeIndex] = mtype;
  output[DataTypeIndex] = dtype;

  memcpy(output + DataStartPosition, img, width * height);

  return true;
}

bool Encoder::encode(float* mat, MESSAGETYPE messagetype, byte* output)
{
  int width = 64, height = 1;
  memcpy(output + MessageWidthIndex, &width, 4);
  memcpy(output + MessageHeightIndex, &height, 4);
  byte mtype = messagetype;
  byte dtype = DATATYPE::FLOAT;
  output[MessageTypeIndex] = mtype;
  output[DataTypeIndex] = dtype;

  memcpy(output + DataStartPosition, mat, width * height);

  return true;
}
bool Encoder::decode(const byte* input, const int recvlen, void** output, 
					int * width, int *height, 
					Encoder::MESSAGETYPE * messagetype, Encoder::DATATYPE * dataType) {

	memcpy(width, input + MessageWidthIndex, 4);
	memcpy(height, input + MessageHeightIndex, 4);
	*messagetype = (MESSAGETYPE)input[MessageTypeIndex];
	*dataType = (DATATYPE)input[DataTypeIndex];
	int totalSize = (*width) * (*height) + HeaderSize;

	if (*messagetype > 7) {
		printf("Invalid MessageType %d\n", input[MessageTypeIndex]);
		return false;
	}else if (*messagetype == Encoder::STRING) {
		(*output) = (byte*)calloc(*width, 1);

		memcpy(*output, input + DataStartPosition, *width);
		return true;
	}
	if (*dataType > 3)
	{
		printf("Invalid DataType %d\n", *dataType);
		return false;
	}
	if (totalSize != recvlen)
	{
		printf("Expected size: %d, but only recieve size: %d\n", totalSize, recvlen);
		return false;
	}

	(*output) = (byte*)calloc((*width) * (*height), 1);

	memcpy(*output, input + DataStartPosition, (*width) * (*height));
	return true;
}
std::tuple<bool, int, int, Encoder::MESSAGETYPE, Encoder::DATATYPE> Encoder::decode(const byte* input,
                                                                                    const int recvlen, void** output)
{
  int width = -1;
  int height = -1;
  byte mtype = 0;
  byte dtype = 0;
  MESSAGETYPE messagetype;
  DATATYPE datatype;
  memcpy(&width, input + MessageWidthIndex, 4);
  memcpy(&height, input + MessageHeightIndex, 4);

  int totalSize = width * height + HeaderSize;

  mtype = input[MessageTypeIndex];
  dtype = input[DataTypeIndex];

  if (mtype > 7)
  {
    printf("Invalid MessageType %d\n", mtype);
    goto FAILDECODE;
  }
  else if (mtype == Encoder::STRING) {
	  (*output) = (byte*)calloc(width, 1);

	  memcpy(*output, input + DataStartPosition, width);
	  return { true, width, 0, Encoder::STRING, (DATATYPE)0 };
  }

  if (dtype > 3)
  {
    printf("Invalid DataType %d\n", dtype);
    goto FAILDECODE;
  }



  messagetype = (MESSAGETYPE)mtype;
  datatype = (DATATYPE)dtype;

  if (totalSize != recvlen)
  {
    printf("Expected size: %d, but only recieve size: %d\n", totalSize, recvlen);
    goto FAILDECODE;
  }

  (*output) = (byte*)calloc(width * height, 1);

  memcpy(*output, input + DataStartPosition, width * height);

  return {true, width, height, messagetype, datatype};

FAILDECODE:
  return {false, width, height, messagetype, datatype };
}

void Encoder::decodeImage(byte* input, byte* output, int size)
{
  memcpy(output, input, size);
}

void Encoder::decodeMat4(byte* input, float* output, int size)
{
  memcpy(output, input, size);
}
