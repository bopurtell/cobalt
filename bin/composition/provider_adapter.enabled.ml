module Provider = Cobalt_markdown.Provider

let factory : Cobalt_ui.Document_decoration_host.Factory.t =
  { available = true
  ; eligible_path = Provider.eligible_path
  ; create = (fun () ->
      let provider = Provider.create () in
      { Cobalt_ui.Document_decoration_host.Session.key =
          (fun ~document ~revision -> Provider.key provider ~document ~revision)
      ; decorate = (fun ~key ~source -> Provider.decorate provider ~key ~source)
      ; close = (fun () -> Provider.close provider)
      })
  }
