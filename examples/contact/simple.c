#include "contact.h"
#include <stdio.h>

#define ff_isOK(status) (status >= 0)

#define ff_errorNo(status) (-(status) >> 8)
#define ff_errorField(status) (-(status) & 0xFF)

#define AllocCopyStr(target, string) \
  target##Len = sizeof(string) - 1;  \
  target = malloc(sizeof(string));   \
  memcpy(target, string, sizeof(string))

int main(int argc, char **argv) {
  (void)argc; (void)argv;

  contact c = contact_new();

  memcpy(c.Magic, "CONTACT", sizeof(c.Magic));
  c.Version = 1;

  AllocCopyStr(c.Name, "THE JOE");
  AllocCopyStr(c.FirstName, "Joe");
  AllocCopyStr(c.LastName, "Schmoe");
  AllocCopyStr(c.Email, "joe@schmoe.co");

  c.BirthdayDay = 13;
  c.BirthdayMonth = 7;
  c.BirthdayYear = 1996;

  c.PhoneNumber = 123456789;

  SDL_RWops *file = SDL_RWFromFile("joe.contact", "wb");
  int status = contact_write(file, c);
  SDL_RWclose(file);
  if(ff_isOK(status)) {
    printf("File write OK. (%d)\n", status);
    printf(": %*.*s '%*.*s' %*.*s <%*.*s>\n",
      (int)(c.FirstNameLen), (int)(c.FirstNameLen), c.FirstName,
      (int)(c.NameLen), (int)(c.NameLen), c.Name,
      (int)(c.LastNameLen), (int)(c.LastNameLen), c.LastName,
      (int)(c.EmailLen), (int)(c.EmailLen), c.Email);
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
      (int)(c.FirstNameLen), (int)(c.FirstNameLen), c.FirstName,
      (int)(c.NameLen), (int)(c.NameLen), c.Name,
      (int)(c.LastNameLen), (int)(c.LastNameLen), c.LastName,
      (int)(c.EmailLen), (int)(c.EmailLen), c.Email);
  } else {
    printf("File read failed: %s\n", contact_formaterror(status));
  }
  contact_free(&c);
  return status;
}