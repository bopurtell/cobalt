open! Core
let lookup session ~path =
  Option.bind (Cobalt_app.Session.find_resource session path) ~f:(fun (_, controller) ->
    match Cobalt_app.Controller.kind controller with
    | Directory -> None
    | File ->
      let editor = Cobalt_app.Controller.editor controller in
      Some (Model.of_buffer ~revision:(Cobalt_core.Editor.revision editor)
        (Cobalt_core.Editor.text editor)))
;;
