# frozen_string_literal: true

require "lutaml/hal"
require_relative "../core/governor"

module Relaton
  module W3c
    #
    # W3C binding of {Relaton::Core::Governor}.
    #
    # The ladder (60 s → 900 s), the per-round escalation, the jitter, the
    # latched give-up and the Retry-After parsing all live in core, where the
    # ITU-R crawler shares them. What is W3C-specific is exactly two things:
    # which errors mean "rate-limited", and which env vars tune the durations.
    #
    class Governor < Relaton::Core::Governor
      # Errors that mean "you are being rate-limited", as opposed to "this
      # resource is broken". api.w3.org signals throttling with **403 as well as
      # 429** — w3c_api's whole faraday-retry layer is built around 403 being the
      # W3C rate-limit signal — so a 403 must never be recorded as a permanently
      # broken resource either. Requires lutaml-hal >= 0.2.5, which gave 403 its
      # own ForbiddenError class (before that it arrived as a bare Error).
      THROTTLE_ERRORS = [
        ::Lutaml::Hal::TooManyRequestsError,
        ::Lutaml::Hal::ForbiddenError,
      ].freeze

      # RELATON_W3C_THROTTLE_BASE / _MAX / _GIVEUP.
      ENV_PREFIX = "RELATON_W3C"
    end
  end
end
