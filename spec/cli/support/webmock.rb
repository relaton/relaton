require "webmock/rspec"

# A developer's RELATON_USE_API / RELATON_API_HOST would turn the API tier
# on (relaton#535) in every Db the suite builds.
%w[RELATON_USE_API RELATON_API_HOST].each { ENV.delete _1 }

RSpec.configure do |config|
  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end
