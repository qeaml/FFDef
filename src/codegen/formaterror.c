#include<stdio.h>
#define BUFFER_SIZE 5120
char {s}_errbuffer[BUFFER_SIZE];
const char *{s}_formaterror(int error) {{
  if(error >= 0) {{
    return "(no error)";
  }}
  const char *mainFormat;
  const unsigned int error_unsigned = ~(error-1);
  const unsigned int error_type = error_unsigned & 0xFF;
  const unsigned int struct_idx = (error_unsigned >> 8) & 0xFF;
  const unsigned int field_idx = (error_unsigned >> 16) & 0xFF;
  switch(error_type) {{
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
    snprintf({s}_errbuffer, BUFFER_SIZE, "(unkown error %u/%u/%u)",
      error_type, struct_idx, field_idx);
    return {s}_errbuffer;
  }}
  snprintf({s}_errbuffer, BUFFER_SIZE, mainFormat,
    {s}_struct_fields[struct_idx][field_idx], {s}_struct_names[struct_idx]);
  return {s}_errbuffer;
}}
