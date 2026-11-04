require "bundler/setup"
require "fileutils"
require "tmpdir"

Dir[File.join(__dir__, "support/**/*.rb")].sort.each { |f| require f }

require "relaton-cli"
require "rspec/html"

# The relaton registry loads flavors lazily (only their processor files), so
# flavor constants like Relaton::Iso::Bibliography are not defined until a fetch.
# Some specs reference those constants directly (e.g. to stub `.get`), so
# eager-load every flavor here. Test process only; runtime stays lazy.
Relaton::Db::Registry::SUPPORTED_GEMS.each do |b|
  require b
rescue LoadError
  nil # flavor gem not present in this environment
end

RSpec.configure do |config|
  # The suite addresses its fixtures through cwd-relative `spec/...` paths
  # (the CLI resolves user paths from the working directory), so each
  # example runs inside a tmpdir that mirrors this suite's data dirs as
  # `spec/...` — the same shape the standalone gem repo provided.
  config.around do |example|
    Dir.mktmpdir("rspec-cli-") do |dir|
      # `spec/fixtures` mirrors (used by the CLI's cwd-relative paths)…
      %w[fixtures assets index_fixtures index_fixtures_static vcr_cassettes]
        .each do |data|
        tmp_data = File.join(dir, "spec", data)
        FileUtils.mkdir_p tmp_data
        src = File.join(__dir__, data)
        FileUtils.cp_r(Dir[File.join(src, "*")], tmp_data) if File.exist?(src)
      end
      # …and the acceptance specs' own fixture dir at its original
      # repo-root-relative location.
      # the CLI writes ./tmp/ outputs relative to the working directory
      FileUtils.mkdir_p File.join(dir, "tmp")
      acc = File.join(__dir__, "acceptance", "fixtures")
      tmp_acc = File.join(dir, "spec", "acceptance", "fixtures")
      FileUtils.mkdir_p tmp_acc
      FileUtils.cp_r(Dir[File.join(acc, "*")], tmp_acc)
      Dir.chdir(dir) { example.run }
    end
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = File.join(__dir__, ".rspec_status")

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!
  config.expose_dsl_globally = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

ISOXML_BLANK_HDR = <<~"HDR".freeze
  <iso-standard xmlns="http://riboseinc.com/isoxml">
  <bibdata type="article">
    <title>
    </title>
    <title>
    </title>
    <docidentifier>
      <project-number>ISO </project-number>
    </docidentifier>
    <contributor>
      <role type="author"/>
      <organization>
        <name>International Organization for Standardization</name>
        <abbreviation>ISO</abbreviation>
      </organization>
    </contributor>
    <contributor>
      <role type="publisher"/>
      <organization>
        <name>International Organization for Standardization</name>
        <abbreviation>ISO</abbreviation>
      </organization>
    </contributor>
    <script>Latn</script>
    <status>
      <stage>60</stage>
      <substage>60</substage>
    </status>
    <copyright>
      <from>#{Time.new.year}</from>
      <owner>
        <organization>
          <name>International Organization for Standardization</name>
          <abbreviation>ISO</abbreviation>
        </organization>
      </owner>
    </copyright>
    <editorialgroup>
      <technical-committee/>
      <subcommittee/>
      <workgroup/>
    </editorialgroup>
  </bibdata>
  </iso-standard>
HDR
