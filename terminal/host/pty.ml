type t
external spawn_raw : string -> int -> int -> t = "cobalt_pty_spawn"
external read : t -> string option = "cobalt_pty_read"
external write_raw : t -> string -> int -> int = "cobalt_pty_write"
external resize_raw : t -> int -> int -> unit = "cobalt_pty_resize"
external poll_exit : t -> string option = "cobalt_pty_poll_exit"
external signal_raw : t -> bool -> unit = "cobalt_pty_signal"
external close : t -> unit = "cobalt_pty_close"
let spawn ~(cwd : string) ~(rows : int) ~(cols : int) : t = spawn_raw cwd rows cols
let write (t : t) (data : string) ~(pos : int) : int = write_raw t data pos
let resize (t : t) ~(rows : int) ~(cols : int) : unit = resize_raw t rows cols
let signal (t : t) ~(force : bool) : unit = signal_raw t force
