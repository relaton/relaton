module TestIdentifier
  class << self
    include Pubid::Core::Identifier
  end
end

class DummyDefaultType < Pubid::Core::Identifier::Base
  extend Forwardable
  def_delegators 'DummyDefaultType', :type
  def to_s
    "#{@publisher} #{@number}"
  end

  def self.type
    { key: :default, title: "Default Type" }
  end

  def root
    self
  end
end


config = Pubid::Core::Configuration.new
config.default_type = DummyDefaultType

TestIdentifier.set_config(config)
