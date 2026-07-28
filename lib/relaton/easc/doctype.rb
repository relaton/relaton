module Relaton
  module Easc
    # EASC document types. Two series, both issued by the Eurasian
    # Economic Standards Council:
    #   * PMG — ПМГ (Правила по межгосударственной стандартизации)
    #   * RMG — РМГ (Рекомендации по межгосударственной стандартизации)
    class Doctype < Bib::Doctype
      TYPES = %w[
        pmg
        rmg
      ].freeze
    end
  end
end
