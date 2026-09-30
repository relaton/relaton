require "lutaml/model"

module Relaton
  class Db
    # One row of the cache index. A row is keyed either by a pubid (`id`, its
    # `to_hash`) or, for a processor with no pubid class, by a string (`key`).
    # `file` names the document in the doc store; several rows can share one
    # file (a query row and the row of the document it returned). A
    # `not_found` row has no file.
    class CacheEntry < Lutaml::Model::Serializable
      DOC = "doc".freeze
      NOT_FOUND = "not_found".freeze

      attribute :id, :hash
      attribute :key, :string
      attribute :status, :string
      attribute :file, :string
      attribute :fetched, :string

      key_value do
        map "id", to: :id
        map "key", to: :key
        map "status", to: :status
        map "file", to: :file
        map "fetched", to: :fetched
      end

      def not_found?
        status == NOT_FOUND
      end
    end
  end
end
