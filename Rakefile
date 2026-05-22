require "rake"
require "fileutils"

# Discover all gems in gems/
GEMS = if Dir.exist?("gems")
         Dir["gems/*/"].map { |dir| File.basename(dir) }.sort.freeze
       else
         [].freeze
       end

# Convert gem name to namespace token (relaton-iso -> relaton_iso)
def gem_to_namespace(gem_name)
  gem_name.tr("-", "_").to_sym
end

def in_gem_dir(gem_name, &block)
  Dir.chdir("gems/#{gem_name}", &block)
end

# Per-gem tasks (dynamically generated)
GEMS.each do |gem_name|
  namespace_name = gem_to_namespace(gem_name)

  namespace :test do
    desc "Run specs for #{gem_name}"
    task namespace_name do
      puts "Testing #{gem_name}..."
      success = Bundler.with_unbundled_env do
        system("cd gems/#{gem_name} && rm -f Gemfile.lock && bundle && bundle exec rake")
      end
      raise "Test failed for #{gem_name}" unless success
    end
  end

  namespace :build do
    desc "Build #{gem_name}"
    task namespace_name do
      puts "Building #{gem_name}..."
      in_gem_dir(gem_name) { sh "gem build *.gemspec" }
    end
  end

  namespace :install do
    desc "Install #{gem_name} locally"
    task namespace_name => "build:#{namespace_name}" do
      puts "Installing #{gem_name}..."
      in_gem_dir(gem_name) do
        gem_file = Dir["*.gem"].first
        sh "gem install #{gem_file}"
      end
    end
  end

  namespace :clean do
    desc "Clean built files for #{gem_name}"
    task namespace_name do
      in_gem_dir(gem_name) { FileUtils.rm_f(Dir["*.gem"]) }
    end
  end

  namespace :release do
    desc "Release #{gem_name} to RubyGems"
    task namespace_name => "build:#{namespace_name}" do
      puts "Releasing #{gem_name}..."
      in_gem_dir(gem_name) do
        gem_file = Dir["*.gem"].first
        sh "gem push #{gem_file}"
      end
    end
  end

  namespace :rubocop do
    desc "Run RuboCop for #{gem_name}"
    task namespace_name do
      in_gem_dir(gem_name) { sh "bundle exec rubocop" }
    end
  end
end

# Aggregate tasks
namespace :test do
  desc "Run all gem specs"
  task :all do
    failures = []
    GEMS.each do |gem_name|
      begin
        Rake::Task["test:#{gem_to_namespace(gem_name)}"].invoke
      rescue StandardError => e
        failures << "#{gem_name}: #{e.message}"
      end
    end
    if failures.any?
      puts "\nFailed gems:"
      failures.each { |f| puts "  ✗ #{f}" }
      exit 1
    end
  end
end

namespace :build do
  desc "Build all gems"
  task :all do
    GEMS.each { |g| Rake::Task["build:#{gem_to_namespace(g)}"].invoke }
  end
end

namespace :install do
  desc "Install all gems locally"
  task :all do
    GEMS.each { |g| Rake::Task["install:#{gem_to_namespace(g)}"].invoke }
  end
end

namespace :clean do
  desc "Clean all built files"
  task :all do
    GEMS.each { |g| Rake::Task["clean:#{gem_to_namespace(g)}"].invoke }
  end
end

namespace :rubocop do
  desc "Run RuboCop for all gems"
  task :all do
    failures = []
    GEMS.each do |gem_name|
      begin
        Rake::Task["rubocop:#{gem_to_namespace(gem_name)}"].invoke
      rescue StandardError => e
        failures << "#{gem_name}: #{e.message}"
      end
    end
    if failures.any?
      puts "\nFailed gems:"
      failures.each { |f| puts "  ✗ #{f}" }
      exit 1
    end
  end
end

# Helper: locate per-gem version.rb (handles 3gpp -> ThreeGpp module path)
def gem_version_file(gem_name)
  if gem_name == "relaton"
    "gems/relaton/lib/relaton/version.rb"
  else
    suffix = gem_name.sub(/^relaton-/, "")
    # Module path: 3gpp lives at lib/relaton/3gpp/version.rb (filesystem)
    "gems/#{gem_name}/lib/relaton/#{suffix}/version.rb"
  end
end

# Read a gem's current version from disk by parsing its gemspec
def gem_current_version(gem_name)
  spec_path = "gems/#{gem_name}/#{gem_name}.gemspec"
  return nil unless File.exist?(spec_path)
  spec = Gem::Specification.load(spec_path)
  spec&.version&.to_s
end

namespace :version do
  desc "Show monorepo master MAJOR.MINOR and per-gem versions"
  task :show do
    require_relative "lib/relaton/version"
    puts "Monorepo master version: #{Relaton::MONOREPO_VERSION}"
    puts
    puts "Per-gem versions:"
    GEMS.each do |g|
      v = gem_current_version(g) || "?"
      puts "  #{g.ljust(22)} #{v}"
    end
  end

  desc "Check that every gem's MAJOR.MINOR matches the master"
  task :check do
    require_relative "lib/relaton/version"
    master_mm = Relaton::MONOREPO_VERSION.split(".")[0, 2].join(".")
    puts "Checking all gems share MAJOR.MINOR = #{master_mm}..."
    bad = []
    GEMS.each do |g|
      v = gem_current_version(g)
      if v && v.split(".")[0, 2].join(".") != master_mm
        bad << "#{g}: #{v}"
      end
    end
    if bad.empty?
      puts "✓ All #{GEMS.size} gems aligned on #{master_mm}"
    else
      puts "✗ Out of sync:"
      bad.each { |x| puts "  - #{x}" }
      exit 1
    end
  end

  desc "Sync the master MAJOR.MINOR to all gems (resets PATCH to 0)"
  task :sync do
    require_relative "lib/relaton/version"
    master = Relaton::MONOREPO_VERSION
    puts "Syncing all gems to #{master} ..."
    GEMS.each do |g|
      Dir.glob("gems/#{g}/lib/**/version.rb").each do |vf|
        content = File.read(vf)
        next unless content.match?(/^\s*VERSION\s*=\s*"/)
        new_content = content.gsub(/(VERSION\s*=\s*)"[^"]+"/, "\\1\"#{master}\"")
        next if content == new_content
        File.write(vf, new_content)
        puts "  ✓ #{vf}"
      end
    end
  end

  desc "Bump master version (rake 'version:bump[major|minor]') and sync to all gems"
  task :bump, [:type] do |_t, args|
    require_relative "lib/relaton/version"
    type = args[:type] || "minor"
    raise "type must be major or minor" unless %w[major minor].include?(type)

    cur = Gem::Version.new(Relaton::MONOREPO_VERSION).segments
    new_v = case type
            when "major" then "#{cur[0] + 1}.0.0"
            when "minor" then "#{cur[0]}.#{cur[1] + 1}.0"
            end
    puts "Bumping master #{Relaton::MONOREPO_VERSION} -> #{new_v}"

    mf = "lib/relaton/version.rb"
    File.write(mf, File.read(mf).gsub(/(MONOREPO_VERSION\s*=\s*)"[^"]+"/,
                                      "\\1\"#{new_v}\""))
    Object.send(:remove_const, :Relaton) if defined?(Relaton)
    load mf
    Rake::Task["version:sync"].invoke
  end

  desc "Bump PATCH for a single gem: rake 'version:bump_patch[relaton-iso]'"
  task :bump_patch, [:gem] do |_t, args|
    g = args[:gem] or raise "gem name required"
    raise "unknown gem: #{g}" unless GEMS.include?(g)
    Dir.glob("gems/#{g}/lib/**/version.rb").each do |vf|
      content = File.read(vf)
      next unless m = content.match(/VERSION\s*=\s*"(\d+)\.(\d+)\.(\d+)"/)
      new_v = "#{m[1]}.#{m[2]}.#{m[3].to_i + 1}"
      File.write(vf, content.sub(m[0], %(VERSION = "#{new_v}")))
      puts "✓ #{g}: #{m[1]}.#{m[2]}.#{m[3]} -> #{new_v}"
    end
  end
end

namespace :release do
  desc "Show release order (from release-order.json)"
  task :show_order do
    require "json"
    config = JSON.parse(File.read("release-order.json"))
    puts "Release order:"
    config["release_order"].each_with_index do |g, i|
      puts "  #{i + 1}. #{g}"
    end
  end

  desc "Validate release-order.json covers every gem in gems/"
  task :validate_order do
    require "json"
    order = JSON.parse(File.read("release-order.json"))["release_order"]
    missing = GEMS - order
    extra = order - GEMS
    if missing.empty? && extra.empty?
      puts "✓ release-order.json valid (#{order.size} gems)"
    else
      puts "✗ missing from release-order: #{missing.join(', ')}" if missing.any?
      puts "✗ unknown gems in release-order: #{extra.join(', ')}" if extra.any?
      exit 1
    end
  end

  desc "Release status summary"
  task :status do
    require_relative "lib/relaton/version"
    Rake::Task["version:check"].invoke rescue nil
    Rake::Task["release:validate_order"].invoke rescue nil
    puts
    puts "Run 'rake test:all' before releasing."
  end
end

# Default task: run all gem specs.
task default: ["test:all"]

# Convenience aliases.
task test: "test:all"
task build: "build:all"
task install: "install:all"
task clean: "clean:all"
