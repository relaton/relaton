# frozen_string_literal: true

require "lutaml/store"

module Relaton
  # Access to LutaML data repositories through lutaml-store — the cloud
  # store (api.relaton.org), a Pages/raw host, or a local GCR-style package,
  # all through one read API with an explicit local package cache.
  #
  # This module composes lutaml-store sources; it is deliberately
  # independent of Relaton::Db's own cache machinery (see
  # relaton#204/#205 for that rework).
  module Cloud
    module_function

    # An explicitly configured source over a LutaML data repository.
    #
    # @param base_url [String] cloud store base (e.g. "https://api.relaton.org")
    # @param collection [String] one collection (for relaton: a flavor)
    # @param options [Hash] passthrough to Lutaml::Store::Source::Rest
    #   (headers:, timeout:, transport:, cache:, default_format:)
    def source(base_url:, collection:, **options)
      Lutaml::Store::Source.for(:rest, base_url: base_url, collection: collection, **options)
    end

    # A local package directory source (a downloaded distribution or a
    # Mirror/Repository pull).
    def local(path)
      Lutaml::Store::Source.for(:directory, path: path)
    end

    # The record's bytes. NotFoundError means the repository definitively
    # does not have the key; BackendError means the network/service broke.
    #
    # @param key [String] the collection's storage key (see .resolve_key)
    def read(key, source:)
      source.read(key)
    end

    # Resolves a reference to the collection's storage key. The contract's
    # keys are URL-safe storage keys; slash-bearing docids live in the
    # manifest's entries[].metadata.docid. Resolution is manifest-driven and
    # explicit: exact storage-key match first, then the docid metadata,
    # then nil — there is no path-encoding guesswork.
    #
    # @param ref [String] a storage key or a primary docidentifier
    # @return [String, nil]
    def resolve_key(ref, source:)
      return ref if source.manifest.key?(ref)

      found = source.manifest.entries.find do |e|
        e.metadata["docid"]&.casecmp?(ref)
      end
      found&.key
    end

    # The parsed record: the model class is declared by the caller — never
    # inferred.
    def get(key, model_class, source:)
      source.get(key, model_class)
    end

    # Mirrors the whole collection into a GCR-style local package.
    #
    # @param into [String] target directory (a `<into>/<collection>` package
    #   is written)
    # @return [Lutaml::Store::Source::Directory] a source over the package
    def pull(source:, into:, collection: nil, force: false)
      Lutaml::Store::Mirror.pull(source, into: into, collection: collection, force: force)
    end

    # Read-through convenience: a Repository over a cloud source with an
    # explicit local package cache; reads served from the cache once pulled.
    def repository(base_url:, collection:, cache_path:, **options)
      Lutaml::Store::Repository.new(
        source: source(base_url: base_url, collection: collection, **options),
        cache: local(cache_path)
      )
    end
  end
end
