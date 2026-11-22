let () =
  Cobalt_cli.run
    ~document_decorations:Cobalt_document_decorations.Provider_adapter.factory
    ~silver_overview:Cobalt_silver_composition.Silver_adapter.factory
