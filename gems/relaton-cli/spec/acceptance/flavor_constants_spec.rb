require "open3"

# `--pubid-flavor` resolves `Relaton::<Flavor>::INDEXFILE` and
# `Pubid::<Flavor>::Identifier`. The per-flavor `autoload` lines live in
# `relaton.rb`, so requiring only `relaton/db` leaves every flavor constant
# undefined and `relaton index --pubid-flavor iso` dies with "no relaton flavor".
#
# This must run in a CLEAN process: `spec_helper` eager-loads every flavor
# (SUPPORTED_GEMS.each { require }) so the constants exist in-suite no matter
# what `relaton-cli.rb` requires — which is exactly why the gap reached a
# release candidate unnoticed.
RSpec.describe "flavor constants after requiring relaton-cli" do
  def in_clean_process(code)
    out, err, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", code)
    # The leptris FFI-fallback notice (leptris#1738: the compiled native
    # layer is unavailable on some runners/rubies and the library engages
    # the FFI surface) is a dependency's loading notice, not this
    # command's output — strip it so the assertions see what the command
    # itself did. Any other stderr still fails.
    err = err.gsub(/^\s*leptris: native acceleration unavailable.*\n/, "")
    # moxml's adapter-fallback notice, same category: leptris's vendored
    # native bridge and the yeptris gem's native ext both register
    # Yeptris::Native on x86_64-linux, and moxml reports the fallback at
    # load time (leptris/yeptris-ruby co-initialization issue). It is a
    # dependency notice, not this command's output.
    err = err.gsub(/^.*moxml: the leptris adapter is installed but unusable.*\n/, "")
    [out, err, status]
  end

  it "resolves a flavor's INDEXFILE without spec_helper's eager load" do
    out, err, status = in_clean_process(
      'require "relaton-cli"; print Relaton.const_get("Iso").const_get(:INDEXFILE)',
    )

    expect(err).to be_empty
    expect(status).to be_success
    expect(out).to eq("index-v2")
  end

  it "resolves a flavor's pubid Identifier" do
    out, _err, status = in_clean_process(
      'require "relaton-cli"; print Pubid.const_get("Iso").const_get(:Identifier)',
    )

    expect(status).to be_success
    expect(out).to eq("Pubid::Iso::Identifier")
  end
end
