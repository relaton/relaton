# frozen_string_literal: true

require "shellwords"

# Exercises `rake build:combined`: the per-gem source trees are vendored into a
# single staged gem at pkg/combined, with a generated gemspec and an autoload
# entry. These specs prove the staged gem is self-contained, loads lazily, and
# routes ISO references — all loaded EXCLUSIVELY from the combined tree.
#
# Tagged :slow because it stages files and shells out to `gem build`.
RSpec.describe "build:combined", :slow do
  def repo_root = File.expand_path("../../../..", __dir__)
  def stage_dir = File.join(repo_root, "pkg", "combined")

  before(:all) do
    require File.join(File.expand_path("../../../..", __dir__),
                      "lib", "relaton", "combined_builder")
    Relaton::CombinedBuilder.build(root: File.expand_path("../../../..",
                                                          __dir__))
  end

  # Load $LOAD_PATH with the staged combined lib FIRST and every in-repo
  # gems/relaton* source lib REMOVED, so `require "relaton"` / "relaton/iso"
  # resolve only from the combined tree (external gems stay available).
  def run_against_combined(body)
    clean = $LOAD_PATH.reject { |p| p.include?("/gems/relaton") }
    paths = [File.join(stage_dir, "lib")] + clean
    script = <<~RUBY
      $LOAD_PATH.replace(#{paths.inspect})
      #{body}
      print "COMBINED_PASS"
    RUBY
    `#{Shellwords.escape(RbConfig.ruby)} -e #{Shellwords.escape(script)} 2>&1`
  end

  it "generates an autoload entry for each vendored flavor" do
    entry = File.read(File.join(stage_dir, "lib", "relaton.rb"))
    expect(entry).to include('autoload :Iso, "relaton/iso"')
    expect(entry).to include('autoload :Iec, "relaton/iec"')
  end

  it "loads relaton, registers ISO, and routes from the combined tree only" do
    out = run_against_combined(<<~RUBY)
      require "relaton"
      reg = Relaton::Db::Registry.instance
      abort "FAIL: routing" unless reg.class_by_ref("ISO 19115") == :relaton_iso
      src = Relaton::Iso::Processor.instance_method(:get).source_location[0]
      abort "FAIL: not from combined tree (\#{src})" unless src.include?("/pkg/combined/")
      abort "FAIL: eager" if Relaton::Iso.const_defined?(:Bibliography, false)
    RUBY
    expect(out).to include("COMBINED_PASS")
  end

  it "produces a combined gemspec with vendored deps, no relaton siblings" do
    spec = Dir.chdir(stage_dir) { Gem::Specification.load("relaton.gemspec") }
    names = spec.dependencies.map(&:name)
    expect(names).to include("pubid", "isoics", "nokogiri")
    expect(names.grep(/\Arelaton-/)).to be_empty
    expect(spec.name).to eq("relaton")
  end

  it "builds a loadable .gem from the staged tree" do
    require "bundler"
    # Clean env so `gem build` doesn't inherit the spec's bundler context and
    # try to resolve this repo's Gemfile from the staged dir.
    built = Bundler.with_unbundled_env do
      Dir.chdir(stage_dir) do
        system("gem build relaton.gemspec >/dev/null 2>&1")
        Dir["relaton-*.gem"].first
      end
    end
    expect(built).not_to be_nil
    expect(File.size(File.join(stage_dir, built))).to be_positive
  end
end
