module Relaton
  module Easc
    # EASC bibliographic item extension. Adds EASC-specific structured
    # metadata on top of the shared Relaton::Bib::Ext so the fields
    # round-trip through both XML and YAML without per-repo merge hacks.
    #
    # Fields:
    #   * urn             — urn:easc:<series>:...
    #   * webpage         — mgscatalog.by detail URL
    #   * session         — МГС council session that adopted the doc
    #                       (e.g. "67МГС", "19МГС")
    #   * developer       — Разработчик (e.g. "Российская Федерация")
    #   * joining_states  — country codes of states that joined
    #                       (collection: e.g. ["АРМ", "БЕИ", "КАЗ"])
    #   * assigned_to     — Закреплен за (e.g. "МТК 536 Методология...")
    class Ext < Bib::Ext
      attribute :doctype,        Doctype
      attribute :urn,            :string
      attribute :webpage,        :string
      attribute :session,        :string
      attribute :developer,      :string
      attribute :joining_states, :string, collection: true, initialize_empty: true
      attribute :assigned_to,    :string

      xml do
        map_element "urn",             to: :urn
        map_element "webpage",         to: :webpage
        map_element "session",         to: :session
        map_element "developer",       to: :developer
        map_element "joining_states",  to: :joining_states
        map_element "assigned_to",     to: :assigned_to
      end

      key_value do
        map_element "urn",             to: :urn
        map_element "webpage",         to: :webpage
        map_element "session",         to: :session
        map_element "developer",       to: :developer
        map_element "joining_states",  to: :joining_states
        map_element "assigned_to",     to: :assigned_to
      end
    end
  end
end
