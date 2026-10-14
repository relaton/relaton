# frozen_string_literal: true

require "leptris"
require "leptris/xml/relaxng"

# RelaxNG validation for the flavor suites, on leptris — replaces the
# Java-based Jing gem (the last Java dependency of the test env).
# Jing's duck: compile the schema once, validate many documents.
class Relaxng
  # @param path [String] the (compile) grammar path; `<include>` chains
  #   resolve relative to the grammar file, as Jing resolved them
  def initialize(path)
    @schema = Leptris::XML::RelaxNG.parse_file path
  end

  # @param file [String] a document path or XML text
  # @return [Array<Hash>] `[{ line:, column:, message: }]`, empty when valid
  def validate(file)
    xml = File.exist?(file.to_s) ? File.read(file) : file.to_s
    @schema.validate_errors Leptris::XML.parse(xml)
  end
end
