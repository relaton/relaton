describe Relaton::Nist::PubsExport do
  subject { Relaton::Nist::PubsExport.instance }

  before do
    Singleton.__init__(Relaton::Nist::PubsExport)
    $ignore_pubs_export = false # rubocop:disable Style/GlobalVars
  end

  after do
    Singleton.__init__(Relaton::Nist::PubsExport)
    $ignore_pubs_export = true # rubocop:disable Style/GlobalVars
  end

  context "update json file" do
    it "when ctime is nil" do
      VCR.use_cassette "json_data" do
        expect(File).to receive(:exist?).with(Relaton::Nist::PubsExport::DATAFILE).at_most(:once).and_return true
        allow(File).to receive(:exist?).and_call_original
        expect(File).to receive(:ctime).and_return(nil).at_most(1).time
        item = subject.data.find { |i| i["docidentifier"] == "FIPS 140-2" }
        expect(item).to be_instance_of Hash
      end
    end

    it "when size of file is zero" do
      expect(File).to receive(:exist?).with(Relaton::Nist::PubsExport::DATAFILE).and_return true
      ctime = Time.now
      expect(File).to receive(:ctime).with(Relaton::Nist::PubsExport::DATAFILE).and_return ctime
      expect(File).to receive(:size).with(Relaton::Nist::PubsExport::DATAFILE).and_return 0
      expect(subject).to receive(:fetch_data).with(ctime)
      subject.data
    end
  end

  context "on a read-only file system (relaton-nist#57)" do
    let(:zip) { File.binread PUBS_EXPORT_ZIP_PATH }
    let(:fips) { a_hash_including("docidentifier" => "FIPS 140-2") }

    # An empty storage dir: a real ~/.relaton cache must not answer for the
    # in-memory branch.
    around do |example|
      storage_dir = Relaton::Index.config.storage_dir
      Dir.mktmpdir("relaton-nist-ro") do |dir|
        Relaton::Index.configure { |c| c.storage_dir = dir }
        example.run
      ensure
        Relaton::Index.configure { |c| c.storage_dir = storage_dir }
      end
    end

    before do
      allow(subject).to receive(:last_modified).and_return Time.now
      allow(subject).to receive(:download).and_return zip
    end

    it "keeps the data in memory when the cache dir cannot be made" do
      expect(FileUtils).to receive(:mkdir_p).and_raise Errno::EROFS
      data = nil
      expect { data = subject.data }.to output(
        /WARN: Cannot write .*Read-only file system.*stays in memory/,
      ).to_stderr_from_any_process
      expect(data).to include fips
      expect(File.exist?(subject.datafile)).to be false
    end

    it "keeps the data in memory when the cache file cannot be written" do
      expect(File).to receive(:binwrite).and_raise Errno::ENOSPC
      data = nil
      expect { data = subject.data }
        .to output(/No space left/).to_stderr_from_any_process
      expect(data).to include fips
      expect(Dir.children(File.dirname(subject.datafile))).to be_empty
    end

    it "reads the fresh download, not a stale cache it cannot replace" do
      FileUtils.mkdir_p File.dirname(subject.datafile)
      File.write subject.datafile, "not a zip"
      allow(File).to receive(:ctime).and_call_original
      allow(File).to receive(:ctime).with(subject.datafile)
        .and_return Time.now - (2 * 86_400)
      expect(File).to receive(:rename).and_raise Errno::EROFS
      data = nil
      expect { data = subject.data }
        .to output(/WARN/).to_stderr_from_any_process
      expect(data).to include fips
    end

    it "writes the cache file when it can" do
      expect(subject.data).to include fips
      expect(File.binread(subject.datafile)).to eq zip
    end
  end

  it "puts the cache file under the relaton-index storage dir" do
    storage_dir = Relaton::Index.config.storage_dir
    Relaton::Index.configure { |c| c.storage_dir = "/var/cache/relaton" }
    # expand_path adds the drive letter on Windows
    path = "/var/cache/relaton/.relaton/nist/pubs-export.zip"
    expect(subject.datafile).to eq File.expand_path(path)
  ensure
    Relaton::Index.configure { |c| c.storage_dir = storage_dir }
  end

  it "returns last modified time from server" do
    last_modified = "Thu, 09 Apr 2026 12:00:00 GMT"
    stub_request(:head, "#{Relaton::Nist::PubsExport::PUBS_EXPORT}.meta")
      .to_return(headers: { "Last-Modified" => last_modified })
    expect(subject.send(:last_modified)).to eq Time.httpdate(last_modified)
  end

  it "thread safe fetch data" do
    expect(File).to receive(:exist?).with(Relaton::Nist::PubsExport::DATAFILE).and_return false
    expect(subject).to receive(:fetch_data).with(nil)
    expect(subject).to receive(:unzip) do
      sleep 0.1
      [{ "docidentifier" => "SP 800-205 (Draft)" }]
    end
    threads = (1..2).map do
      Thread.new { Thread.current[:data] = subject.data }
    end
    threads.each(&:join)
    threads.each do |t|
      expect(t[:data]).to eq [{ "docidentifier" => "SP 800-205 (Draft)" }]
    end
  end
end
