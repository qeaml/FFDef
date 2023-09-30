#include "contact.h"
#include <stdio.h>

#define ff_isOK(status) (status >= 0)

#define ff_errorNo(status) (-(status) >> 8)
#define ff_errorField(status) (-(status) & 0xFF)

#define AllocCopyStrAlt(data, len, string) \
  len = sizeof(string) - 1;                \
  data = malloc(sizeof(string));           \
  memcpy(data, string, len)

#define AllocCopyStr(target, string) \
  AllocCopyStrAlt(target.data, target.len, string)

#define StrFmtAlt(len, data) \
  (int)(len), (int)(len), (data)

#define StrFmt(string) \
  StrFmtAlt(string.len, string.data)

int main(int argc, char **argv) {
  (void)argc; (void)argv;

  contact c = contact_new();

  AllocCopyStrAlt(c.name, c.nameLen, "THE JOE");
  AllocCopyStr(c.firstName, "Joe");
  AllocCopyStr(c.lastName, "Schmoe");
  AllocCopyStr(c.email, "joe@schmoe.co");

  c.birthdayDay = 13;
  c.birthdayMonth = 7;
  c.birthdayYear = 1996;

  c.phoneNumber = 123456789;

  SDL_RWops *file = SDL_RWFromFile("joe.contact", "wb");
  int status = contact_write(file, c);
  SDL_RWclose(file);
  if(ff_isOK(status)) {
    printf("File write OK. (%d)\n", status);
    printf(": %*.*s '%*.*s' %*.*s <%*.*s>\n",
      StrFmt(c.firstName), StrFmtAlt(c.nameLen, c.name), StrFmt(c.lastName),
      StrFmt(c.email));
    contact_free(&c);
  } else {
    printf("File write failed: %s\n", contact_formaterror(status));
    contact_free(&c);
    return status;
  }

  file = SDL_RWFromFile("joe.contact", "rb");
  status = contact_read(file, &c);
  SDL_RWclose(file);
  if(ff_isOK(status)) {
    printf("File read OK. (%d)\n", status);
    printf(": %*.*s '%*.*s' %*.*s <%*.*s>\n",
      StrFmt(c.firstName), StrFmtAlt(c.nameLen, c.name), StrFmt(c.lastName),
      StrFmt(c.email));
  } else {
    printf("File read failed: %s\n", contact_formaterror(status));
  }
  contact_free(&c);
  return status;
}