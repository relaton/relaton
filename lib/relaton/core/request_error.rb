module Relaton
  # Transport failure while fetching remote data; `Relaton::Db#net_retry`
  # retries it. It depends on nothing, so `relaton/index` requires this file
  # alone and does not load the rest of `relaton/core`.
  #
  # The class is named `Relaton::RequestError`, not `Relaton::Core::...`: an
  # error raised without a message uses the class name as its message, and
  # relaton-cli prints that message.
  class RequestError < StandardError; end

  module Core
    RequestError = Relaton::RequestError
  end
end
