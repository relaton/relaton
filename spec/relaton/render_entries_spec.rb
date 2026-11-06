# frozen_string_literal: true

# The consolidation ships the render engine inside the relaton gem, and
# TWO require entries must keep resolving to it: `require
# "relaton-render"` (the standalone gem's documented umbrella) and
# `require "relaton/render"` (the retired gem's primary entry file). The
# facade file (lib/relaton/render.rb) is what keeps the latter from
# raising LoadError in a relaton-only bundle — or, worse, from falling
# through to a still-bundled retired gem whose own lib/relaton/render.rb
# shadows it. Fresh-process requires, because a require is once-only per
# process and the point is precisely that a clean one resolves.
RSpec.describe "the render require entries" do
  let(:lib) { File.expand_path("../../lib", __dir__) }

  def fresh_require(entry)
    script = <<~RB
      require "#{entry}"
      puts Relaton::Render::Unrenderable.name
      puts Relaton::Render::General.name if defined?(Relaton::Render::General)
    RB
    IO.popen([Gem.ruby, "-I", lib, "-e", script], err: %i[child out], &:read)
  end

  it 'require "relaton-render" defines the surface' do
    out = fresh_require("relaton-render")
    expect(out).to include("Relaton::Render::Unrenderable")
    expect(out).to include("Relaton::Render::General")
  end

  it 'require "relaton/render" defines the surface' do
    out = fresh_require("relaton/render")
    expect(out).to include("Relaton::Render::Unrenderable")
    expect(out).to include("Relaton::Render::General")
  end
end
