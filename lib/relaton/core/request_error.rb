module Relaton
  # The base of relaton's own errors. It depends on nothing, so
  # `relaton/index` requires this file alone and does not load the rest of
  # `relaton/core`.
  class Error < StandardError; end

  # Transport failure while fetching remote data; `Relaton::Db#net_retry`
  # retries it.
  #
  # The class is named `Relaton::RequestError`, not `Relaton::Core::...`: an
  # error raised without a message uses the class name as its message, and
  # relaton-cli prints that message. relaton-bib also declares this name
  # (< StandardError) and may load first: reopen instead of redefining,
  # or the coexisting require of both gems dies on a superclass mismatch.
  # relaton-bib also declares this name (< StandardError) and may load
  # first; redefining it (< Error) dies on a superclass mismatch, so
  # declare only when absent — both forms rescue as StandardError
  class RequestError < Error; end unless defined?(Relaton::RequestError)

  # Offline mode (`Relaton::Db.configuration.offline`, RELATON_OFFLINE) and
  # the local store has no entry for the reference (relaton#536). Not a
  # RequestError: `Relaton::Db#net_retry` must not retry it, since no
  # request was made.
  class NotInLocalStoreError < Error
    # @return [String] the reference the local store lacks
    attr_reader :reference

    # @param reference [String]
    # @param dirs [Array<String>] the cache directories that were read
    def initialize(reference, dirs = [])
      @reference = reference
      where = dirs.empty? ? "no cache directory" : dirs.join(", ")
      super("`#{reference}` is not in the local store (#{where}); " \
            "offline mode makes no network request")
    end
  end

  # `Relaton::Db` found no flavor for a reference: no flavor's pubid grammar
  # reads it exactly, and no flavor's prefix matches it. relaton-cli rescues
  # it, logs the message and returns no document.
  class UnknownReferenceError < Error
    # @return [String] the reference no flavor recognizes
    attr_reader :reference

    # @param reference [String]
    def initialize(reference)
      @reference = reference
      super("`#{reference}` is not a recognized standards identifier")
    end
  end

  module Core
    RequestError = Relaton::RequestError
  end
end
