#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <errno.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

/* Unix.terminal_io cannot represent every native flag/baud-rate bit. Keep the
   original structure so leaving the frontend restores the caller's exact mode. */
CAMLprim value cobalt_terminal_mode_capture(value unit)
{
  CAMLparam1(unit);
  struct termios mode;
  memset(&mode, 0, sizeof(mode));
  int result;
  do { result = tcgetattr(STDIN_FILENO, &mode); }
  while (result < 0 && errno == EINTR);
  if (result < 0) caml_failwith("cannot capture terminal mode");
  CAMLreturn(caml_alloc_initialized_string(sizeof(mode), (const char *)&mode));
}

CAMLprim value cobalt_terminal_mode_restore(value snapshot)
{
  CAMLparam1(snapshot);
  struct termios mode;
  if (caml_string_length(snapshot) != sizeof(mode))
    caml_invalid_argument("invalid terminal mode snapshot");
  memcpy(&mode, String_val(snapshot), sizeof(mode));
  int result;
  do { result = tcsetattr(STDIN_FILENO, TCSANOW, &mode); }
  while (result < 0 && errno == EINTR);
  if (result < 0) caml_failwith("cannot restore terminal mode");
  CAMLreturn(Val_unit);
}
