# frozen_string_literal: true

require "mechanize"
require_relative "../core/governor"

module Relaton
  module Itu
    #
    # ITU binding of {Relaton::Core::Governor}, for the ITU-R crawl.
    #
    # ITU does not signal throttling with a distinct exception class the way
    # api.w3.org does, so membership is decided by status *code* and by one
    # marker module rather than by an error hierarchy. Measured over a
    # 49-minute full run, the F5 WAF in front of www.itu.int answers `/rec`
    # with **HTTP 503** and `/pub` with a **302 to notfound.aspx** — a soft
    # block Mechanize follows to a perfectly good 200, indistinguishable from
    # "no such document" unless the crawler marks it (see
    # `DataCrawlerR::SoftBlock`, which includes {SoftBlock} for exactly this).
    #
    # Why a governor at all, when `DataCrawlerR#get` already retries: a rate
    # limit is a *pool* event. One worker's 503 must pause every other worker,
    # for a window that outlasts the ban, instead of four workers each running
    # their own 5/10/15 s ladder and keeping the limiter engaged. That is the
    # failure the W3C crawl spent 4 h 56 m in before this class existed.
    #
    class Governor < Relaton::Core::Governor
      # Mixed into the crawler's soft-block error. A module rather than a class
      # so the exception can stay a `Mechanize::ResponseCodeError` subclass —
      # which is what keeps `#get`'s existing rescue list unchanged — while
      # still being distinguishable from the 404 it otherwise looks like.
      module SoftBlock; end

      # Response codes that mean "the WAF is pushing back", as opposed to "that
      # document is not there" or "that record is broken".
      #
      # **500 is deliberately absent.** Same call the W3C governor makes: a
      # persistent 5xx on one resource is a broken record, and routing it here
      # would open a pool-wide cooldown for every bad page in the corpus. Only
      # 503 (measured, on /rec) and the gateway codes, which are infrastructure
      # rather than content, get the pool treatment.
      THROTTLE_CODES = %w[429 502 503 504].freeze

      # RELATON_ITU_THROTTLE_BASE / _MAX / _GIVEUP.
      ENV_PREFIX = "RELATON_ITU"

      # @param error [StandardError]
      # @return [Boolean]
      def self.throttle?(error)
        return true if error.is_a? SoftBlock
        return false unless error.is_a? ::Mechanize::ResponseCodeError

        THROTTLE_CODES.include? error.response_code.to_s
      end
    end
  end
end
