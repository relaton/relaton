RSpec.describe Relaton::Storage do
  context "API mode" do
    before(:each) do
      Relaton.configure do |config|
        config.api_mode = true
      end
      Singleton.__init__ Relaton::Storage
    end

    after(:each) do
      Relaton.configure do |config|
        config.api_mode = false
      end
      Singleton.__init__ Relaton::Storage
    end

    let(:storage) { Relaton::Storage.instance }
    let(:bucket) { "test-bucket" }

    it "save document to S3" do
      dir = "cahche/iso"
      # file = "doc.xml"
      body = "<doc>Test doc</doc>"
      key = File.join dir, "doc.xml"
      client = double "AwsClient"
      expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket).twice
      expect(client).to receive(:head_object).with(bucket: bucket, key: "cahche/iso/version")
      expect(client).to receive(:put_object).with(bucket: bucket, key: key, body: body)
      expect(Aws::S3::Client).to receive(:new).and_return client
      storage.save dir, key, body
    end

    it "read document from S3" do
      dir = "cahche/iso"
      # file = "doc.xml"
      body = "<doc>Test doc</doc>"
      key = File.join dir, "doc"
      client = double "AwsClient"
      item = double "Item", key: "#{key}.xml"
      list = double "List", contents: [item]
      obj_body = double "Body", read: body
      obj = double "Object", body: obj_body
      expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket).twice
      expect(client).to receive(:list_objects_v2).with(bucket: bucket, prefix: "#{key}.").and_return list
      expect(client).to receive(:get_object).with(bucket: bucket, key: "#{key}.xml").and_return obj
      expect(Aws::S3::Client).to receive(:new).and_return client
      expect(storage.get(key)).to eq body
    end

    it "return all the documents from S3" do
      dir = "cahche/iso"
      # file = "doc.xml"
      body = "<doc>Test doc</doc>"
      key = File.join dir, "doc.xml"
      client = double "AwsClient"
      expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket).twice
      item = double "Item", key: key
      list = double "List", contents: [item]
      obj_body = double "Body", read: body
      obj = double "Object", body: obj_body
      expect(client).to receive(:list_objects_v2).with(bucket: bucket, prefix: dir).and_return list
      expect(client).to receive(:get_object).with(bucket: bucket, key: key).and_return obj
      expect(Aws::S3::Client).to receive(:new).and_return client
      contents = storage.all dir
      expect(contents).to eq [body]
    end

    it "set version" do
      dir = "cahche/iso"
      key = File.join dir, "version"
      hash = Relaton::Registry.instance.by_type("iso").grammar_hash
      client = double "AwsClient"
      expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket).twice
      # expect(ENV).to receive(:[]).and_call_original
      error = Aws::S3::Errors::NotFound.new Seahorse::Client::RequestContext.new, ""
      expect(client).to receive(:head_object).with(bucket: bucket, key: key).and_raise error
      expect(client).to receive(:put_object).with(bucket: bucket, key: key, body: hash)
      expect(Aws::S3::Client).to receive(:new).and_return client
      storage.send :set_version, dir
    end

    context "check version" do
      it "valid" do
        dir = "cahche/iso"
        key = File.join dir, "version"
        hash = Relaton::Registry.instance.by_type("iso").grammar_hash
        client = double "AwsClient"
        obj_body = double "Body", read: hash
        obj = double "Object", body: obj_body
        expect(client).to receive(:get_object).with(bucket: bucket, key: key).and_return obj
        expect(Aws::S3::Client).to receive(:new).and_return client
        expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket)
        expect(storage.check_version?(dir)).to be true
      end

      it "version file doesn't exist" do
        dir = "cahche/iso"
        key = File.join dir, "version"
        # hash = "invalid"
        client = double "AwsClient"
        # obj_body = double "Body", read: hash
        # obj = double "Object", body: obj_body
        error = Aws::S3::Errors::NoSuchKey.new Seahorse::Client::RequestContext.new, ""
        expect(client).to receive(:get_object).with(bucket: bucket, key: key).and_raise error
        expect(Aws::S3::Client).to receive(:new).and_return client
        expect(ENV).to receive(:[]).with("AWS_BUCKET").and_return(bucket)
        expect(storage.check_version?(dir)).to be false
      end
    end
  end
end
