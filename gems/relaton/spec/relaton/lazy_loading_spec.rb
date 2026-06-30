# frozen_string_literal: true

require "shellwords"

# These specs prove that registering the flavor processors does NOT eagerly
# load each flavor's heavy main file (`relaton/iso`, ...). The assertions run
# in a clean subprocess because the umbrella suite stubs
# `Relaton::Iso::Bibliography.get` and otherwise touches flavor code, which
# would pre-load `iso.rb` and mask the behaviour under test.
RSpec.describe "lazy flavor loading" do
  def marker = "LAZYLOAD_PASS"

  # Run a Ruby snippet in a fresh process that inherits this process's
  # $LOAD_PATH (so bundled gems and in-repo lib trees resolve) but none of its
  # loaded code. The snippet prints `marker` on success; anything else (a
  # NameError, an `abort "FAIL: ..."`) leaves it absent. Returns combined
  # stdout+stderr, which may carry unrelated log noise — assertions tolerate it.
  def run_in_clean_process(body)
    script = <<~RUBY
      $LOAD_PATH.replace(#{$LOAD_PATH.inspect})
      #{body}
      print "#{marker}"
    RUBY
    `#{Shellwords.escape(RbConfig.ruby)} -e #{Shellwords.escape(script)} 2>&1`
  end

  it "registers the ISO processor without loading the heavy iso.rb" do
    out = run_in_clean_process(<<~RUBY)
      require "relaton/db"
      Relaton::Db::Registry.instance
      unless defined?(Relaton::Iso::Processor)
        abort "FAIL: Iso::Processor was not registered"
      end
      if Relaton::Iso.const_defined?(:Bibliography, false)
        abort "FAIL: Iso::Bibliography was eagerly loaded"
      end
    RUBY
    expect(out).to include(marker)
  end

  it "loads the heavy iso.rb lazily once a processor method needs it" do
    out = run_in_clean_process(<<~RUBY)
      require "relaton/db"
      proc = Relaton::Db::Registry.instance.processor_by_ref("ISO 19115")
      abort "FAIL: pre-loaded" if Relaton::Iso.const_defined?(:Bibliography, false)
      proc.grammar_hash # triggers require_relative "../iso"
      abort "FAIL: not loaded after use" unless Relaton::Iso.const_defined?(:Bibliography, false)
    RUBY
    expect(out).to include(marker)
  end

  it "clears caches with no flavor preloaded (remove_index_file self-loads)" do
    out = run_in_clean_process(<<~RUBY)
      require "relaton/db"
      db = Relaton::Db.new(nil, nil)
      db.clear # iterates every processor's remove_index_file
    RUBY
    expect(out).to include(marker)
  end

  # grammar_hash is reachable cold via Db#fetch -> Cache.grammar_hash; every
  # processor's grammar_hash must self-load its constants (incl. Digest).
  it "computes grammar_hash on the cold path for representative flavors" do
    out = run_in_clean_process(<<~RUBY)
      require "relaton/db"
      reg = Relaton::Db::Registry.instance
      %w[ISO IEC ETSI].each do |type|
        hash = reg.by_type(type).grammar_hash
        abort "FAIL: \#{type} grammar_hash" unless hash.is_a?(String) && !hash.empty?
      end
    RUBY
    expect(out).to include(marker)
  end

  # from_yaml is reachable cold via Db cache reads (deserialize without a prior
  # fetch), so every processor's from_yaml must self-load its Item constant.
  # ecma/gb regressed here when the registry stopped eager-loading flavors.
  it "deserializes from_yaml on the cold path without preloading the flavor" do
    out = run_in_clean_process(<<~RUBY)
      require "relaton/db"
      reg = Relaton::Db::Registry.instance
      yaml = "docid:\\n  - id: X 1\\n    type: T\\n    primary: true\\n"
      %w[relaton_ecma relaton_gb].each do |short|
        begin
          reg.find_processor(short).from_yaml(yaml)
        rescue NameError => e
          abort "FAIL: \#{short} from_yaml NameError: \#{e.message}"
        rescue StandardError
          # parse/validation errors are fine — we only guard against NameError
        end
      end
    RUBY
    expect(out).to include(marker)
  end
end
