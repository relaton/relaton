require "canon"
require "webmock/rspec"
require "relaton/easc"

RSpec.configure do |config|
  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
