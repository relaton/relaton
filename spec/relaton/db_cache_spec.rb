RSpec.describe Relaton::DbCache do
  it "creates default caches" do
    cache_path = File.expand_path("~/.relaton/cache")
    FileUtils.mv cache_path, "relaton1/cache", force: true
    FileUtils.rm_rf %w(relaton)
    Relaton::DbCache.init_bib_caches(
      global_cache: true, local_cache: "", flush_caches: true,
    )
    expect(File.exist?(cache_path)).to be true
    expect(File.exist?("relaton")).to be true
    FileUtils.mv "relaton1/cache", cache_path if File.exist? "relaton1"
  end
end
