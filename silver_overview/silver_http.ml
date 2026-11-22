open! Core
open! Async

(* This small HTTP client intentionally has no DNS, proxy, redirect, or TLS
   machinery. Silver's v1 native endpoint is a loopback HTTP server. *)
let max_body_bytes = 2 * 1024 * 1024
let max_header_bytes = 16 * 1024

let parse_endpoint text =
  let invalid () =
    failwith "Silver endpoint must be http://localhost:PORT, http://127.0.0.1:PORT, or http://[::1]:PORT"
  in
  let text = String.chop_suffix text ~suffix:"/" |> Option.value ~default:text in
  let host, addr, port =
    List.find_map
      [ "localhost", "127.0.0.1"; "127.0.0.1", "127.0.0.1"; "[::1]", "::1" ]
      ~f:(fun (host, addr) ->
        String.chop_prefix text ~prefix:("http://" ^ host ^ ":")
        |> Option.map ~f:(fun port -> host, addr, port))
    |> Option.value_or_thunk ~default:invalid
  in
  if String.is_empty port || String.length port > 5 || not (String.for_all port ~f:Char.is_digit)
  then invalid ();
  let port = Int.of_string port in
  if port < 1 || port > 65535 then invalid ();
  host, addr, port
;;

let normalize_endpoint text =
  try
    let host, _, port = parse_endpoint text in
    Ok (Printf.sprintf "http://%s:%d" host port)
  with
  | Failure message -> Error message
;;

let endpoint text =
  let host, addr, port = parse_endpoint text in
  let address = Unix.Inet_addr.of_string addr in
  let remote = Socket.Address.Inet.create address ~port in
  Printf.sprintf "%s:%d" host port, Tcp.Where_to_connect.of_inet_address remote, addr
;;

let ipv6_socket () =
  (* Async's [Socket.Type.tcp] creates IPv4 sockets by default. Supply an IPv6
     descriptor explicitly for the bracketed loopback endpoint. *)
  let fd = Core_unix.socket ~close_on_exec:true ~domain:PF_INET6 ~kind:SOCK_STREAM ~protocol:0 () in
  let fd = Fd.create (Socket `Unconnected) fd (Info.of_string "Silver IPv6 socket") in
  Socket.of_fd fd Socket.Type.tcp
;;

let line reader ~max =
  match%map Reader.read_until_bounded reader (`Char '\n') ~keep_delim:false ~max with
  | `Ok text ->
    (match String.chop_suffix text ~suffix:"\r" with
     | Some line -> line
     | None -> failwith "Malformed Silver HTTP line")
  | `Max_exceeded _ -> failwith "Silver HTTP line exceeds the size limit"
  | `Eof | `Eof_without_delim _ -> failwith "Incomplete Silver HTTP response"
;;

let rec framing reader ~remaining ~length ~chunked =
  let%bind header = line reader ~max:remaining in
  if String.is_empty header
  then return (length, chunked)
  else (
    let remaining = remaining - String.length header - 2 in
    if remaining < 2 then failwith "Silver HTTP headers exceed the size limit";
    match String.lsplit2 header ~on:':' with
    | Some (name, value) ->
      let value = String.strip value in
      (match String.lowercase name with
       | "content-length" ->
         if Option.is_some length || String.is_empty value || not (String.for_all value ~f:Char.is_digit)
         then failwith "Invalid Silver HTTP Content-Length";
         let n = Int.of_string_opt value in
         (match n with
          | Some n when n <= max_body_bytes -> framing reader ~remaining ~length:(Some n) ~chunked
          | _ -> failwith "Silver HTTP body exceeds the size limit")
       | "transfer-encoding" ->
         if chunked || not (String.Caseless.equal value "chunked")
         then failwith "Unsupported Silver HTTP Transfer-Encoding";
         framing reader ~remaining ~length ~chunked:true
       | _ -> framing reader ~remaining ~length ~chunked)
    | None -> failwith "Malformed Silver HTTP header")
;;

let read_exact reader size =
  let buffer = Bytes.create size in
  match%map Reader.really_read reader buffer with
  | `Ok -> Bytes.unsafe_to_string ~no_mutation_while_string_reachable:buffer
  | `Eof _ -> failwith "Incomplete Silver HTTP body"
;;

let read_chunked reader =
  let buffer = Buffer.create 4096 in
  let rec loop remaining framing_budget =
    let%bind header = line reader ~max:(Int.min 1024 framing_budget) in
    let framing_budget = framing_budget - String.length header - 4 in
    if framing_budget < 2 then failwith "Silver HTTP chunk framing exceeds the size limit";
    let size, _ = String.lsplit2 header ~on:';' |> Option.value ~default:(header, "") in
    if String.is_empty size || not (String.for_all size ~f:Char.is_hex_digit)
    then failwith "Malformed Silver HTTP chunk";
    match Int.of_string_opt ("0x" ^ size) with
    | Some 0 ->
      let%map _ = framing reader ~remaining:framing_budget ~length:None ~chunked:false in
      Buffer.contents buffer
    | Some size when size > 0 && size <= remaining ->
      let%bind chunk = read_exact reader size in
      let%bind ending = read_exact reader 2 in
      if not (String.equal ending "\r\n") then failwith "Malformed Silver HTTP chunk ending";
      Buffer.add_string buffer chunk;
      loop (remaining - size) framing_budget
    | _ -> failwith "Silver HTTP body exceeds the size limit"
  in
  loop max_body_bytes max_header_bytes
;;

let read_response reader =
  let%bind status_line = line reader ~max:1024 in
  let status =
    match String.split status_line ~on:' ' with
    | ("HTTP/1.0" | "HTTP/1.1") :: code :: _
      when String.length code = 3 && String.for_all code ~f:Char.is_digit -> Int.of_string code
    | _ -> failwith "Malformed Silver HTTP status"
  in
  let%bind length, chunked =
    framing reader ~remaining:max_header_bytes ~length:None ~chunked:false
  in
  let%map body =
    match length, chunked with
    | Some length, false -> read_exact reader length
    | None, true -> read_chunked reader
    | _ -> failwith "Unsupported Silver HTTP body framing"
  in
  status, body
;;

let request ~endpoint:text ~timeout ~stop ~meth ~path ~headers ~body =
  let request_stop = Ivar.create () in
  let stop_request () = Ivar.fill_if_empty request_stop () in
  let abandoned = Ivar.read request_stop in
  let work =
    Monitor.try_with (fun () ->
      let host, remote, addr = endpoint text in
      let socket = if String.equal addr "::1" then Some (ipv6_socket ()) else None in
      Tcp.with_connection ?socket ~interrupt:abandoned remote (fun _ reader writer ->
        if Ivar.is_full request_stop
        then return (Error "Silver HTTP request abandoned")
        else (
          let meth = match meth with `Get -> "GET" | `Post -> "POST" in
          Writer.writef writer "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n"
            meth path host;
          List.iter headers ~f:(fun (name, value) ->
            Writer.writef writer "%s: %s\r\n" name value);
          Writer.writef writer "Content-Length: %d\r\n\r\n%s" (String.length body) body;
           (* A close may make the reader fail after [abandoned] wins. Keep that
              exception local rather than leaking it into Tcp.with_connection. *)
           let response = Monitor.try_with (fun () -> read_response reader) in
           Deferred.choose
            [ Deferred.choice abandoned (fun () ->
                (* Close just this transport, even if the peer never reads our write. *)
                don't_wait_for (Writer.close writer ~force_close:Deferred.unit);
                Error "Silver HTTP request abandoned")
             ; Deferred.choice response (function
                 | Ok reply -> Ok reply
                 | Error exn -> Error (Exn.to_string exn))
            ])))
  in
  let%map result =
    Clock_ns.with_timeout timeout
      (Deferred.choose
         [ Deferred.choice stop (fun () -> Error "Silver HTTP request abandoned")
         ; Deferred.choice work (function Ok result -> result | Error exn -> Error (Exn.to_string exn))
         ])
  in
  stop_request ();
  match result with
  | `Result result -> result
  | `Timeout -> Error "Silver HTTP request timed out"
;;
