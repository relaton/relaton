# frozen_string_literal: true

# The supplement part of the hit sort key. It reads the supplement's `number`
# and `year`, which every pubid version answers. pubid removes the
# `supplement_number` and `supplement_year` aliases.
RSpec.describe Relaton::Cen::HitCollection do
  def supplement_key(ref)
    described_class.new(ref).send(:supplement_key, Relaton::Cen::Bibliography.parse(ref))
  end

  it "keys an amendment on its type, number and year" do
    expect(supplement_key("EN 13250:2000/A1:2005")).to eq %w[amendment 1 2005]
  end

  it "keys a consolidated amendment on its type, number and year" do
    expect(supplement_key("EN 285:2015+A1:2021")).to eq %w[amendment 1 2021]
  end

  it "keys a corrigendum without a number on its type and year" do
    expect(supplement_key("EN 13250:2000/AC:2002")).to eq ["corrigendum", "", "2002"]
  end

  it "keys a base document on empty strings" do
    expect(supplement_key("EN 13250:2000")).to eq ["", "", ""]
  end
end
