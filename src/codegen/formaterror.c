#include<stdio.h>
#define cBufferSz 5120
char gBuffer[cBufferSz];
const char *{s}_formaterror(int error) {{
  if(error >= 0) {{
    return "(no error)";
  }}
  const char *mainFormat;
  switch(error & 0xFF) {{
  case 0x01:
    mainFormat = "Could not write field '%s' of '%s'.";
    break;
  case 0x02:
    mainFormat = "Could not read field '%s' of '%s'.";
    break;
  case 0x03:
    mainFormat = "Invalid value for field '%s' of '%s'.";
    break;
  default:
    return "(unknown error)";
  }}
  const int struct_idx = (error >> 8) & 0xFF;
  const int field_idx = (error >> 16) & 0xFF;
  snprintf(gBuffer, cBufferSz, mainFormat,
    struct_names[struct_idx], struct_fields[struct_idx][field_idx]);
  return gBuffer;
}}