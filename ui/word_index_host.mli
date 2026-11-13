open! Core
open! Async
type t
val create : unit -> t
val follow : t -> Cobalt_screen.Ui_state.word_index_request option -> unit
val next : t -> (Cobalt_screen.Ui_state.word_index_request * Cobalt_completion.Model.Buffer_words.t) option Deferred.t
val stop : t -> unit
