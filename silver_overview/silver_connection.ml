open! Core
open! Async

type source =
  | Advertised
  | Known
  | Explicit

type candidate =
  { endpoint : string
  ; source : source
  ; instance_id : string option
  }

let endpoint t = t.endpoint
let source t = t.source

type lookup =
  { candidates : candidate list
  ; advertisement_error : string option
  }

module Metadata = struct
  type t =
    { endpoint : string
    ; instance_id : string
    ; pid : int
    }
  [@@deriving of_sexp]
end

let candidate source ?instance_id text =
  Result.map (Silver_http.normalize_endpoint (String.strip text)) ~f:(fun endpoint ->
    { endpoint; source; instance_id })
;;

let explicit text = candidate Explicit text

exception Conflicting_state_directories of string

let native_directory () =
  let nonempty_env name =
    Option.filter (Sys.getenv name) ~f:(Fn.non String.is_empty)
  in
  let root =
    match nonempty_env "XDG_RUNTIME_DIR" with
    | Some root -> root
    | None ->
      Option.value_or_thunk (nonempty_env "XDG_STATE_HOME") ~default:(fun () ->
        Filename.concat (Sys_unix.home_directory ()) ".local/state")
  in
  (* Match Silver's native runtime selection, including existing legacy state.
     Do not silently choose between two independent daemon/share histories. *)
  let canonical = Filename.concat root "silver" in
  let legacy = Filename.concat root "hardcaml-workbench" in
  let exists path =
    try ignore (Core_unix.lstat path : Core_unix.stats); true with
    | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> false
  in
  match exists canonical, exists legacy with
  | true, true ->
    raise (Conflicting_state_directories
             (sprintf "Conflicting Silver state directories: %s and %s" canonical legacy))
  | false, true -> legacy
  | _ -> canonical
;;

exception Invalid_advertisement

let max_metadata_bytes = 8192

let read_bounded fd ~max_bytes =
  let buf = Bytes.create (max_bytes + 1) in
  let rec read pos =
    if pos > max_bytes then raise Invalid_advertisement;
    let n = Core_unix.read ~restart:true ~pos ~len:(Bytes.length buf - pos) fd ~buf in
    if n = 0 then Stdlib.Bytes.sub_string buf 0 pos else read (pos + n)
  in
  read 0
;;

let read_file path =
  let before = Core_unix.lstat path in
  let valid (st : Core_unix.stats) =
    Poly.equal st.st_kind Core_unix.S_REG
    && st.st_uid = Core_unix.geteuid ()
    && st.st_perm land 0o022 = 0
    && Int64.(st.st_size <= of_int max_metadata_bytes)
  in
  if not (valid before) then raise Invalid_advertisement;
  let fd = Core_unix.openfile path ~mode:[ O_RDONLY; O_CLOEXEC; O_NONBLOCK ] in
  Exn.protect ~finally:(fun () -> Core_unix.close fd) ~f:(fun () ->
    let after = Core_unix.fstat fd in
    if not (valid after) || before.st_dev <> after.st_dev || before.st_ino <> after.st_ino
    then raise Invalid_advertisement;
    read_bounded fd ~max_bytes:max_metadata_bytes)
;;

let read_advertisement directory =
  try
    let directory = Option.value_or_thunk directory ~default:native_directory in
    let body = read_file (Filename.concat directory "daemon.sexp") in
    let ({ endpoint; instance_id; pid } : Metadata.t) = Sexp.of_string body |> Metadata.t_of_sexp in
    if pid <= 0
       || String.is_empty instance_id
       || String.length instance_id > 4096
       || String.exists instance_id ~f:(fun c -> Char.to_int c < 32 || Char.equal c '\127')
    then raise Invalid_advertisement;
    (match candidate Advertised ~instance_id endpoint with
     | Ok advertised -> Ok (Some advertised)
     | Error reason -> Error ("Invalid Silver daemon advertisement: " ^ reason))
  with
  | Conflicting_state_directories error -> Error error
  | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> Ok None
  | Core_unix.Unix_error _ -> Error "Cannot read Silver daemon advertisement"
  | _ -> Error "Invalid Silver daemon advertisement"
;;

let lookup ?directory ?(known = []) () =
  let%map advertisement = In_thread.run (fun () -> read_advertisement directory) in
  let advertised, advertisement_error =
    match advertisement with
    | Ok advertised -> Option.to_list advertised, None
    | Error error -> [], Some error
  in
  let known = List.filter_map known ~f:(fun text -> candidate Known text |> Result.ok) in
  let _, choices =
    List.fold (advertised @ known) ~init:(Set.empty (module String), []) ~f:(fun (seen, acc) c ->
      let key =
        match String.chop_prefix c.endpoint ~prefix:"http://localhost:" with
        | None -> c.endpoint
        | Some port -> "http://127.0.0.1:" ^ port
      in
      if Set.mem seen key then seen, acc else Set.add seen key, c :: acc)
  in
  { candidates = List.rev choices; advertisement_error }
;;

let connect ?peer ?timeout { endpoint; instance_id; _ } ~project_root =
  Silver_overview.Testing.connect
    ?peer ?timeout ?expected_instance_id:instance_id ~endpoint ~project_root ()
;;

module Share = struct
  type mode = Embedded | Attached [@@deriving equal]

  module Offer = struct
    type t =
      { offer_id : string
      ; endpoint : string
      ; instance_id : string
      ; project_id : string
      ; project_root : string
      ; mode : string option [@sexp.option]
      }
    [@@deriving of_sexp, equal]
  end

  type publication =
    { directory : string
    ; name : string
    ; registry : int * int
    ; inode : int * int
    ; change_time : float
    ; body : string
    }
  [@@deriving equal]

  type source = Fixture of string | Live of publication
  type t = { source : source; offer : Offer.t; mode : mode option }
  type lookup = { shares : t list; error : string option }

  let offer_id t = t.offer.offer_id
  let endpoint t = t.offer.endpoint
  let instance_id t = t.offer.instance_id
  let project_id t = t.offer.project_id
  let project_root t = t.offer.project_root
  let mode t = t.mode

  let safe_text text =
    not (String.is_empty text) && String.length text <= 4096
    && not (String.exists text ~f:(fun c -> Char.to_int c < 32 || Char.equal c '\127'))
  ;;

  let parse sexp =
    try
      let offer = Offer.t_of_sexp sexp in
      if not (List.for_all [ offer.offer_id; offer.instance_id; offer.project_id; offer.project_root ]
                ~f:safe_text)
         || Filename.is_relative offer.project_root
      then raise Invalid_advertisement;
      let endpoint = Silver_http.normalize_endpoint offer.endpoint |> Result.ok_or_failwith in
      Ok { offer with endpoint }
    with _ -> Error ()
  ;;

  let read file =
    try
      if Filename.is_relative file then raise Invalid_advertisement;
      let dir = Core_unix.lstat (Filename.dirname file) in
      if not (Poly.equal dir.st_kind Core_unix.S_DIR)
         || dir.st_uid <> Core_unix.geteuid ()
         || dir.st_perm land 0o077 <> 0
      then raise Invalid_advertisement;
      let offers =
        match Sexp.of_string (read_file file) with
        | Sexp.List (Sexp.Atom "cobalt-share-fixture-v1" :: offers)
          when List.length offers <= 32 -> offers
        | _ -> raise Invalid_advertisement
      in
      let parsed = List.map offers ~f:parse in
      let ids =
        (* Even a malformed row cannot reuse a valid row's offer ID. *)
        List.concat_map offers ~f:(function
          | Sexp.List fields ->
            List.filter_map fields ~f:(function
              | Sexp.List [ Sexp.Atom "offer_id"; Sexp.Atom id ] -> Some id
              | _ -> None)
          | _ -> [])
      in
      let duplicates = List.find_all_dups ids ~compare:String.compare |> Set.of_list (module String) in
      let shares =
        List.filter_map parsed ~f:(function
           | Ok offer when not (Set.mem duplicates offer.offer_id) ->
             Some { source = Fixture file; offer; mode = None }
          | _ -> None)
      in
      { shares
      ; error =
          Option.some_if (List.length shares <> List.length offers)
            "Ignored malformed or duplicate Silver shares"
      }
    with
    | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> { shares = []; error = None }
    | _ -> { shares = []; error = Some "Cannot read Silver shares: malformed or unsafe fixture" }
  ;;

  let lookup ~file = In_thread.run (fun () -> read file)

  external open_at
    : Core_unix.File_descr.t option -> string -> bool -> Core_unix.File_descr.t
    = "cobalt_silver_share_open"

  external names : Core_unix.File_descr.t -> string array = "cobalt_silver_share_names"

  let with_fd parent name ~directory ~f =
    let fd = open_at parent name directory in
    Exn.protect ~f:(fun () -> f fd) ~finally:(fun () -> Core_unix.close fd)
  ;;

  let inode (st : Core_unix.stats) = st.st_dev, st.st_ino

  let with_registry directory ~f =
    let uid = Core_unix.geteuid () in
    let checked_dir parent name ~private_ ~f =
      with_fd parent name ~directory:true ~f:(fun fd ->
        let st = Core_unix.fstat fd in
        let valid =
          if private_
          then st.st_uid = uid && st.st_perm = 0o700
          else
            (st.st_uid = uid || st.st_uid = 0)
            && (st.st_perm land 0o022 = 0 || (st.st_uid = 0 && st.st_perm land 0o1000 <> 0))
        in
        if not valid then raise Invalid_advertisement;
        f fd)
    in
    if Filename.is_relative directory || String.contains directory '\000'
       || String.length directory > 4096
    then raise Invalid_advertisement;
    let path = String.split directory ~on:'/' |> List.filter ~f:(Fn.non String.is_empty) in
    if List.is_empty path || List.length path > 64
       || List.exists path ~f:(function "." | ".." -> true | _ -> false)
    then raise Invalid_advertisement;
    let rec descend parent = function
      | [] ->
        checked_dir (Some parent) "editor-shares" ~private_:true ~f:(fun shares ->
          checked_dir (Some shares) "v1" ~private_:true ~f)
      | name :: rest ->
        checked_dir (Some parent) name ~private_:(List.is_empty rest)
          ~f:(fun fd -> descend fd rest)
    in
    checked_dir None "/" ~private_:false ~f:(fun root -> descend root path)
  ;;

  let offer_id_of_name name =
    match String.chop_suffix name ~suffix:".sexp" with
    | Some id when String.length id = 32
                   && String.for_all id ~f:(function '0'..'9' | 'a'..'f' -> true | _ -> false) ->
      Some id
    | _ -> None
  ;;

  exception Unavailable

  let max_offer_bytes = 16 * 1024

  let read_live directory registry name id =
    let registry_id = inode (Core_unix.fstat registry) in
    with_fd (Some registry) name ~directory:false ~f:(fun fd ->
      let check fd =
        let st = Core_unix.fstat fd in
        if not (Poly.equal st.st_kind Core_unix.S_REG)
           || st.st_uid <> Core_unix.geteuid ()
           || st.st_perm <> 0o600
           || st.st_nlink <> 1
           || Int64.(st.st_size > of_int max_offer_bytes)
        then raise Invalid_advertisement;
        st
      in
      let st = check fd in
      let require_publisher () =
        (* This is BSD flock (LOCK_SH|LOCK_NB), not POSIX record locking. If
           granted, closing our independently opened fd releases our lock. *)
        if Core_unix.flock fd Core_unix.Flock_command.lock_shared then raise Unavailable
      in
      require_publisher ();
      let body = read_bounded fd ~max_bytes:max_offer_bytes in
      let offer, mode =
        match Sexp.of_string body with
        | Sexp.List [ Sexp.Atom "silver-editor-share-v1"; fields ] ->
          (match parse fields with
           | Ok ({ offer_id; mode = Some "embedded"; _ } as offer) when String.equal offer_id id ->
             offer, Embedded
           | Ok ({ offer_id; mode = Some "attached"; _ } as offer) when String.equal offer_id id ->
             offer, Attached
           | _ -> raise Invalid_advertisement)
        | _ -> raise Invalid_advertisement
      in
      (* Resolve the name again through the current private registry. An open,
         locked descriptor to a withdrawn name is not a live publication. *)
      with_registry directory ~f:(fun current ->
        if not (Poly.equal registry_id (inode (Core_unix.fstat current)))
        then raise Unavailable;
        with_fd (Some current) name ~directory:false ~f:(fun named ->
          let named = check named in
          if not (Poly.equal (inode named) (inode st)) || not (Float.equal named.st_ctime st.st_ctime)
          then raise Unavailable;
          require_publisher ()));
      let publication =
        { directory; name; registry = registry_id; inode = inode st; change_time = st.st_ctime; body }
      in
      { source = Live publication; offer; mode = Some mode })
  ;;

  let read_registry directory =
    try
      with_registry directory ~f:(fun registry ->
        let invalid = ref false in
        let shares =
          names registry |> Array.to_list |> List.sort ~compare:String.compare
          |> List.filter_map ~f:(fun name ->
            Option.bind (offer_id_of_name name) ~f:(fun id ->
              try Some (read_live directory registry name id) with
              | Unavailable | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> None
              | _ -> invalid := true; None))
        in
        { shares; error = Option.some_if !invalid "Ignored malformed or unsafe Silver shares" })
    with
    | Core_unix.Unix_error (Core_unix.ENOENT, _, _) -> { shares = []; error = None }
    | _ -> { shares = []; error = Some "Cannot read Silver shares: unsafe or oversized registry" }
  ;;

  let lookup_live ?directory () =
    In_thread.run (fun () ->
      try
        let directory = Option.value_or_thunk directory ~default:native_directory in
        read_registry directory
      with
      | Conflicting_state_directories error -> { shares = []; error = Some error }
      | _ -> { shares = []; error = Some "Cannot locate Silver shares" })
  ;;

  let revalidate share =
    let withdrawn = "Silver share was withdrawn or changed; rediscover" in
    match share.source with
    | Fixture file ->
      let%map latest = lookup ~file in
      if List.exists latest.shares ~f:(fun candidate -> Offer.equal share.offer candidate.offer)
      then Ok ()
      else Error (Option.value latest.error ~default:withdrawn)
    | Live old ->
      In_thread.run (fun () ->
        try
          with_registry old.directory ~f:(fun registry ->
            match (read_live old.directory registry old.name (offer_id share)).source with
            | Live current when equal_publication old current -> Ok ()
            | _ -> Error withdrawn)
        with _ -> Error withdrawn)
  ;;

  let connect ?peer ?timeout share =
    match%bind revalidate share with
    | Error _ as error -> return error
    | Ok () ->
      (match%bind Silver_overview.Testing.attach_existing ?peer ?timeout
          ~instance_id:(instance_id share) ~endpoint:(endpoint share)
          ~project_root:(project_root share) ~project_id:(project_id share) () with
       | Error reason -> return (Error ("Cannot verify Silver share: " ^ reason))
       | Ok project ->
         match%map revalidate share with
         | Ok () -> Ok project
         | Error _ as error -> Silver_overview.Testing.close project; error)
  ;;
end
