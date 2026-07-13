require "webmock/rspec"
require "tmpdir"

RSpec.configure do |config|
  # Every example gets a fresh, isolated on-disk cache dir and a clean store, so
  # the memoized index never leaks between examples and never touches ~/.relaton.
  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!

    Relaton::Sdo.instance_variable_set(:@configuration, nil)
    Relaton::Sdo.configuration.storage_dir = Dir.mktmpdir("relaton-sdo-spec")
    Relaton::Sdo::Store.instance.reset!
  end
end
