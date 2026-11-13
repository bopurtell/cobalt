(** Capture stdin's complete native terminal settings before changing input flags
    or starting the frontend. Registers a final restoration after Async shutdown;
    the returned function can also restore the snapshot explicitly, once. *)
val save : unit -> (unit -> unit)
