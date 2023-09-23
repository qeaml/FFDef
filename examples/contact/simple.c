#include "contact.h"
#include <stdio.h>

#define ff_isOK(status) (status >= 0)

#define ff_errorNo(status) (-(status) >> 8)
#define ff_errorField(status) (-(status) & 0xFF)

int main(int argc, char **argv) {
  (void)argc; (void)argv;

  contact c = new_contact();

  memcpy(c.Magic, "CONTACT", sizeof(c.Magic));
  c.Version = 1;

  c.Name = "THE JOE";
  c.NameLen = 7;

  c.FirstName = "Joe";
  c.FirstNameLen = 3;
  c.LastName = "Schmoe";
  c.LastNameLen = 6;

  c.Email = "joe@schmoe.co";
  c.EmailLen = 13;

  c.BirthdayDay = 13;
  c.BirthdayMonth = 7;
  c.BirthdayYear = 1996;

  c.PhoneNumber = 123456789;

  SDL_RWops *file = SDL_RWFromFile("joe.contact", "wb");
  int status = contact_write(file, c);
  SDL_RWclose(file);
  if(ff_isOK(status)) {
    printf("File write OK.\n");
  } else {
    printf("File write failed: error %d at field %d\n", ff_errorNo(status), ff_errorField(status));
    return status;
  }

  file = SDL_RWFromFile("joe.contact", "rb");
  status = contact_read(file, &c);
  SDL_RWclose(file);
  if(ff_isOK(status)) {
    printf("File read OK.\n");
  } else {
    printf("File read failed: error %d at field %d\n", ff_errorNo(status), ff_errorField(status));
  }
  free_contact(&c);
  return status;
}