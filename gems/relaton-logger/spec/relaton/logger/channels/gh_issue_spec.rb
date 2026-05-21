describe Relaton::Logger::Channels::GhIssue do
  subject { Relaton::Logger::Channels::GhIssue.new "owner/repo", "title" }

  it "initialize" do
    expect do
      expect(subject.instance_variable_get :@repo).to eq "owner/repo"
      expect(subject.instance_variable_get :@title).to eq "title"
      expect(subject.instance_variable_get :@log).to be_instance_of Set
    end.to output("GITHUB_TOKEN is not set!\n").to_stdout
  end

  it "write" do
    subject.write "string"
    expect(subject.instance_variable_get(:@log).to_a).to eq ["string"]
  end

  it "close" do
    expect(subject.close).to be_nil
  end

  context "create_issue" do
    it "empty log" do
      expect(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return "token"
      expect(subject).not_to receive(:post_issue)
      subject.create_issue
    end

    it "no GITHUB_TOKEN" do
      subject.write "string"
      expect(subject).not_to receive(:post_issue)
      subject.create_issue
    end

    context do
      before do
        subject.write "string"
        expect(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return "token"
      end

      it "success" do
        expect(subject).to receive(:post_issue).and_return double(code: "201")
        expect { subject.create_issue }.to output("Issue created!\n").to_stdout
      end

      it "failed" do
        expect(subject).to receive(:post_issue).and_return double(code: "400", message: "message", body: "body")
        expect { subject.create_issue }.to output("Failed to create issue: 400 message\nbody\n").to_stdout
      end
    end
  end

  it "post_issue" do
    uri = URI("https://api.github.com/repos/owner/repo/issues")
    http = double "http"
    expect(Net::HTTP).to receive(:new).with(uri.host, uri.port).and_return http
    expect(http).to receive(:use_ssl=).with true
    request = double "request"
    expect(Net::HTTP::Post).to receive(:new).with(uri.request_uri, anything).and_return request
    expect(request).to receive(:body=).with "{\"title\":\"title\",\"body\":\"\"}"
    expect(http).to receive(:request).with request
    subject.send :post_issue
  end

  it "issue_body" do
    subject.write "string"
    expect(subject.send :issue_body).to eq({ title: "title", body: "string" })
  end

  it "headers" do
    expect(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("token").twice
    expect(subject.send :headers).to eq({
      "Content-Type" => "application/json",
      "Accept" => "application/vnd.github+json",
      "Authorization" => "Bearer token",
      "X-GitHub-Api-Version" => "2022-11-28",
    })
  end
end
