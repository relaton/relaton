# frozen_string_literal: true

require_relative "../spec_helper"
require "relaton/bib"
require "iso_690_test_suite"

# Runs the implementation-neutral ISO 690 conformance test suite
# (github.com/relaton/iso-690-test-suite): inputs are relaton bibitem
# XML, expected outputs are strings keyed by rendering style and
# language. ISO690_TEST_SUITE points at an alternative checkout.
RSpec.describe "ISO 690 conformance corpus" do
  tests_dir = ENV["ISO690_TEST_SUITE"] || Iso690TestSuite.tests_dir
  corpus_files = Dir[File.join(tests_dir, "*.yaml")].sort

  it "has corpus files" do
    expect(corpus_files).not_to be_empty
  end

  corpus_files.each do |file|
    YAML.safe_load_file(file, aliases: true).each do |test|
      full_name = "#{test.fetch('id')}: #{test.fetch('description')}"

      it full_name do
        pending test.fetch("pending") if test["pending"]

        model = Relaton::Bib::Bibitem.from_xml(test.dig("given", "bibitem"))
        test.dig("expect", "rendering").each do |style, languages|
          languages.each do |lang, expected|
            rendered = Relaton::Render::Iso690::Renderer
              .render(model, style: style, lang: lang)
            expect(rendered).to eq expected
          end
        end
      end
    end
  end
end
