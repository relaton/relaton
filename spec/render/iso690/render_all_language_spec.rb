require_relative "../spec_helper"
require "relaton/bib"

RSpec.describe "render_all per-item language" do
  let(:collection) do
    <<~XML
      <references>
        <bibitem type="standard" id="ja1">
          <title type="main" language="ja">規格の参照方法</title>
          <docidentifier type="JIS">JIS Z 8401</docidentifier>
          <language>ja</language>
          <script>Jpan</script>
        </bibitem>
        <bibitem type="standard" id="en1">
          <title type="main" language="en">English standard title</title>
          <docidentifier type="ISO">ISO 1234</docidentifier>
          <language>en</language>
          <script>Latn</script>
        </bibitem>
      </references>
    XML
  end

  it "renders each reference in its own language within a ja document" do
    general = Relaton::Render::General.new(language: "ja")
    ret = general.render_all(collection)
    expect(ret["ja1"][:formattedref]).to include("規格の参照方法")
    expect(ret["ja1"][:formattedref]).not_to match(/English standard title/)
    expect(ret["en1"][:formattedref]).to include("English standard title")
  end

  it "falls back to the document language for items without one" do
    no_lang = collection.sub("<language>en</language>\n          <script>Latn</script>", "")
    general = Relaton::Render::General.new(language: "ja")
    ret = general.render_all(no_lang)
    expect(ret["en1"][:formattedref]).to include("English standard title")
  end
end
