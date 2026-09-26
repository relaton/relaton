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
      manifest = begin
        source.manifest
      rescue Lutaml::Store::NotFoundError
        # a fresh local package holds no manifest yet — it holds no keys
        return nil
      end

      return ref if manifest.key?(ref)

      found = manifest.entries.find do |e|
        e.metadata["docid"]&.casecmp?(ref)
      end
      found&.key
    end

    # The parsed record: the model class is declared by the caller — never
    # inferred.
    def get(key, model_class, source:)
      source.get(key, model_class)
    end

    # Reference in, parsed model out: resolves the reference through the
    # manifest, reads the record (from the cloud source, or the local
    # package when one is given), and deserializes with the caller's model
    # class. The record's format is self-describing (Format.guess), so the
    # same call serves YAML, JSON and XML records.
    #
    # @param ref [String] a storage key or a primary docidentifier
    # @param model_class [Class] e.g. Relaton::Bib::Item (YAML/JSON
    #   records) or Relaton::Bib::Bibdata (XML bibdata records)
    # @param cache [Lutaml::Store::Source::Directory, nil] read-through
    #   local package (writes through on a miss)
    # @return the model instance
    def fetch(ref, model_class, source:, cache: nil)
      if cache
        # Offline-first: resolve and read against the local package before
        # touching the source — its manifest carries the same docid metadata.
        local_key = resolve_key(ref, source: cache)
        if local_key
          return deserialize(cache.read(local_key), model_class)
        end
      end

      key = resolve_key(ref, source: source)
      raise Lutaml::Store::NotFoundError, "unknown reference: #{ref.inspect}" unless key

      body = if cache
               Lutaml::Store::Repository.new(source: source, cache: cache).read(key)
             else
               source.read(key)
             end

      deserialize(body, model_class)
    end

    def deserialize(body, model_class)
      Lutaml::Store::Format.resolve(Lutaml::Store::Format.guess(body))
                           .deserialize(body, model_class)
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
