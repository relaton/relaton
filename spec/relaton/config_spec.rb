require "spec_helper"

RSpec.describe Relaton::Config do
  before { restore_to_default_config }
  after { restore_to_default_config }

  describe ".configure" do
    it "allows user to set custom configuration" do
      log_types = ["info", :warning, :error]

      Relaton.configuration.logs = log_types

      expect(Relaton.configuration.logs).to eq(log_types)
    end
  end

  def restore_to_default_config
    Relaton.configuration.logs = %i(warning error)
  end
end
