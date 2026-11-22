#define _GNU_SOURCE
/* Work through directory descriptors so that checking a directory and then
 * opening an offer cannot follow a substituted path or symlink. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/unixsupport.h>

CAMLprim value cobalt_silver_share_open(value parent, value name, value directory)
{
  int flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK;
  if (Bool_val(directory)) flags |= O_DIRECTORY;
  int fd = openat(Is_long(parent) ? AT_FDCWD : Int_val(Field(parent, 0)),
                  String_val(name), flags);
  if (fd < 0) caml_uerror("openat", name);
  return Val_int(fd);
}

/* Count all entries except . and .., including unrecognized filenames.
 * Read at most one beyond the cap to detect overflow, never list partially. */
CAMLprim value cobalt_silver_share_names(value fd)
{
  CAMLparam1(fd);
  CAMLlocal2(names, name);
  enum { limit = 256 };
  char entries[limit][256];
  int count = 0, error = 0, overflow = 0;
  int listing = openat(Int_val(fd), ".", O_RDONLY | O_CLOEXEC | O_DIRECTORY);
  if (listing < 0) caml_uerror("openat", Nothing);
  DIR *dir = fdopendir(listing);
  if (!dir) {
    error = errno;
    close(listing);
    errno = error;
    caml_uerror("fdopendir", Nothing);
  }
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(dir);
    if (!entry) {
      error = errno;
      break;
    }
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    size_t len = strlen(entry->d_name);
    if (count == limit || len >= sizeof(entries[0])) {
      overflow = 1;
      break;
    }
    memcpy(entries[count++], entry->d_name, len + 1);
  }
  closedir(dir);
  if (error) {
    errno = error;
    caml_uerror("readdir", Nothing);
  }
  if (overflow) caml_failwith("Silver share registry exceeds its entry limit");
  names = caml_alloc(count, 0);
  for (int i = 0; i < count; ++i) {
    name = caml_copy_string(entries[i]);
    Store_field(names, i, name);
  }
  CAMLreturn(names);
}
