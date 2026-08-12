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

      context "no open issue with this title" do
        before { expect(subject).to receive(:open_issue_number).and_return nil }

        it "success" do
          expect(subject).to receive(:post_issue).and_return double(code: "201")
          expect { subject.create_issue }.to output("Issue created!\n").to_stdout
        end

        it "failed" do
          expect(subject).to receive(:post_issue).and_return double(code: "400", message: "message", body: "body")
          expect { subject.create_issue }.to output("Failed to report issue: 400 message\nbody\n").to_stdout
        end
      end

      context "an open issue with this title exists" do
        before { expect(subject).to receive(:open_issue_number).and_return 42 }

        it "comments on it instead of opening a duplicate" do
          expect(subject).not_to receive(:post_issue)
          expect(subject).to receive(:post_comment).with(42).and_return double(code: "201")
          expect { subject.create_issue }.to output("Issue 42 commented!\n").to_stdout
        end
      end
    end
  end

  context "open_issue_number" do
    let(:uri) do
      u = URI("https://api.github.com/search/issues")
      u.query = URI.encode_www_form(
        q: "repo:owner/repo is:issue is:open in:title \"title\"", per_page: 100
      )
      u
    end

    it "returns the number of the exact-title match" do
      body = { items: [{ number: 7, title: "title other" }, { number: 8, title: "title" }] }.to_json
      expect(subject).to receive(:get).with(uri).and_return double(code: "200", body: body)
      expect(subject.send(:open_issue_number)).to eq 8
    end

    it "returns nil when nothing matches" do
      body = { items: [{ number: 7, title: "unrelated" }] }.to_json
      expect(subject).to receive(:get).with(uri).and_return double(code: "200", body: body)
      expect(subject.send(:open_issue_number)).to be_nil
    end

    it "degrades to nil when the search fails" do
      expect(subject).to receive(:get).and_return double(code: "403", body: "")
      expect(subject.send(:open_issue_number)).to be_nil
    end

    it "degrades to nil when the request raises" do
      expect(subject).to receive(:get).and_raise SocketError, "no network"
      expect { expect(subject.send(:open_issue_number)).to be_nil }
        .to output(/Failed to search for an open `title` issue: no network/).to_stdout
    end
  end

  it "post_comment" do
    subject.write "string"
    uri = URI("https://api.github.com/repos/owner/repo/issues/42/comments")
    expect(subject).to receive(:post).with(uri, { body: "string" })
    subject.send :post_comment, 42
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

  context "body" do
    it "passes a short log through unchanged" do
      subject.write "one"
      subject.write "two"
      expect(subject.send(:body)).to eq "one\ntwo"
    end

    it "truncates on whole lines and says how many were dropped" do
      line = "x" * 1000
      2_000.times { |i| subject.write "#{i} #{line}" } # ~2MB, far over the API limit
      body = subject.send :body
      expect(body.length).to be <= described_class::MAX_BODY
      expect(body).to match(/\n…and \d+ more \(see the run log\)\z/)
      # whole lines only — the last kept line is not cut mid-way
      expect(body.lines[-3]).to end_with "#{line}\n"
    end
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
