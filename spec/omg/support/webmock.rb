require "webmock/rspec"
require "relaton/index"

RSpec.configure do |config|
  config.before(:each) do
    WebMock.reset!
    WebMock.disable_net_connect!
  end
end

# Pre-seeds the Relaton::Index pool with the published index-v2 shape so the
# machine-index consumer specs run offline (the cie/nist pattern).
module OmgIndexFixture
  INDEX_FIXTURE = File.expand_path("../fixtures/index-v2.yaml", __dir__)
  DOC_FIXTURE = File.expand_path("../fixtures/neg-1.0.yaml", __dir__)

  def self.preload
    type = Relaton::Index::Type.new(:omg, file: INDEX_FIXTURE, pubid_class: ::Pubid::Omg::Identifier)
    type.index
    # The runtime call passes pages_url: (relaton#206); the legacy cache
    # removal still passes url: — both resolve to this pre-seeded type.
    type.define_singleton_method(:actual?) do |**args|
      args.key?(:url) || args.key?(:pages_url)
    end
    Relaton::Index.pool.instance_variable_get(:@pool)[:OMG] = type
  end
end

RSpec.configure do |config|
  config.before(:suite) { OmgIndexFixture.preload }
end
