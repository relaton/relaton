# frozen_string_literal: true

require "bundler/setup"
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "relaton"
require "zip"
require "net/http"
require "tmpdir"
require "fileutils"

# The published index of a flavor, fetched once per run and cached in a
# tempdir. Rows deserialize through the flavor's own pubid_class — the same
# path Relaton::Index uses, so a corpus row that fails here fails in the
# consumer too.
module Corpus
  # A stable cache, not a per-process tempdir: a broken DNS window must not
  # turn a green run red. CORPUS_REFRESH=1 forces a re-download.
  CACHE = File.join(Dir.tmpdir, "relaton-corpus-cache")
  FileUtils.mkdir_p(CACHE)

  OPEN_TIMEOUT = 15
  READ_TIMEOUT = 120
  ATTEMPTS = 3

  def self.fetch_index(flavor, branch, indexfile, repo = flavor)
    zip = File.join(CACHE, "#{repo}-#{branch}-#{indexfile}.zip")
    cached = File.exist?(zip) && File.size(zip).positive?
    unless cached && ENV["CORPUS_REFRESH"].to_s != "1"
      download(zip, "https://raw.githubusercontent.com/relaton/relaton-data-#{repo}/#{branch}/#{indexfile}.zip")
    end
    yaml = Zip::File.open(zip) do |z|
      entry = z.entries.reject(&:directory?).first
      raise "empty corpus zip for #{flavor}" unless entry

      entry.get_input_stream.read
    end
    rows = YAML.unsafe_load(yaml)
    rows.map { |r| r[:id] }
  end

  def self.download(zip, url)
    ATTEMPTS.times do |i|
      begin
        uri = URI(url)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                  open_timeout: OPEN_TIMEOUT,
                                                  read_timeout: READ_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        raise "corpus fetch failed: HTTP #{res.code}" unless res.code == "200"

        tmp = "#{zip}.#{Process.pid}.tmp"
        File.binwrite(tmp, res.body)
        File.rename(tmp, zip)
        return
      rescue StandardError
        raise if i == ATTEMPTS - 1

        sleep(2**i)
      end
    end
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
end
