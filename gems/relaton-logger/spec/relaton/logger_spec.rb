# frozen_string_literal: true

RSpec.describe Relaton::Logger do
  before(:each) do
    Relaton::Logger.instance_variable_set :@configuration, nil
  end

  it "has a version number" do
    expect(Relaton::Logger::VERSION).not_to be nil
  end

  it "logger" do
    expect(Relaton.logger_pool).to be_instance_of Relaton::Logger::Pool
  end

  context "log" do
    it "with progname" do
      expect { Relaton.logger_pool.info "msg", "progname" }.to output("[progname] INFO: msg\n").to_stderr
    end

    it "without progname" do
      expect { Relaton.logger_pool.info "msg" }.to output("INFO: msg\n").to_stderr
    end

    it "with key" do
      expect { Relaton.logger_pool.warn "msg", key: "key" }.to output("WARN: (key) msg\n").to_stderr
    end

    it "use block" do
      expect do
        Relaton.logger_pool.error("progname", key: "key") { "msg" }
      end.to output("[progname] ERROR: (key) msg\n").to_stderr
    end

    it "JSON" do
      Relaton::Logger.configure do |config|
        config.logger_pool[:default] = Relaton::Logger::Log.new($stderr, formatter: Relaton::Logger::FormatterJSON)
      end
      expect do
        Relaton.logger_pool.info "Test log", "Prog Name", key: "Key"
      end.to output(
        "{\"prog\":\"Prog Name\",\"message\":\"Test log\",\"severity\":\"INFO\",\"key\":\"Key\"}\n"
      ).to_stderr_from_any_process
    end

    context "log to file" do
      it "use string formatter" do
        Relaton::Logger.configure do |config|
          config.logger_pool[:default] = Relaton::Logger::Log.new("spec/fixtures/log.log")
        end
        Relaton.logger_pool.info "Test log", "Prog Name", key: "Key"
        expect(File.read("spec/fixtures/log.log")).to match(/\[Prog Name\] INFO: \(Key\) Test log/)
        Relaton.logger_pool.truncate
        expect(File.read("spec/fixtures/log.log")).to eq ""
      end

      it "use json formatter" do
        Relaton::Logger.configure do |config|
          config.logger_pool[:default] = Relaton::Logger::Log.new(
            "spec/fixtures/log.json", formatter: Relaton::Logger::FormatterJSON
          )
        end
        Relaton.logger_pool.truncate
        expect(File.read("spec/fixtures/log.json")).to eq ""
        Relaton.logger_pool.info "Test log", "Prog Name", key: "Key1"
        Relaton.logger_pool.info "Test log", "Prog Name", key: "Key2"
        log = File.readlines("spec/fixtures/log.json").map { |l| JSON.parse l }
        expect(log).to eq [
          { "prog" => "Prog Name", "message" => "Test log", "severity" => "INFO", "key" => "Key1" },
          { "prog" => "Prog Name", "message" => "Test log", "severity" => "INFO", "key" => "Key2" }
        ]
      end
    end

    it "tog to GH issue" do
      allow(ENV).to receive(:[]).with("GITHUB_TOKEN").and_return("token")
      log = Relaton::Logger::Channels::GhIssue.new "owner/repo", "title"
      Relaton::Logger.configure do |config|
        config.logger_pool[:default] = Relaton::Logger::Log.new(log, levels: [:error])
      end
      Relaton.logger_pool.error "Test log", "Prog Name", key: "Key"
      http = double "http"
      expect(http).to receive(:use_ssl=).with true
      expect(Net::HTTP).to receive(:new).and_return http
      request = double "request"
      expect(request).to receive(:body=).with "{\"title\":\"title\",\"body\":\"[Prog Name] ERROR: (Key) Test log\\n\"}"
      expect(Net::HTTP::Post).to receive(:new).and_return request
      expect(http).to receive(:request).with(request).and_return double(code: "201")
      log.create_issue
    end

    it "truncate" do
      io = StringIO.new
      Relaton::Logger.configure do |config|
        config.logger_pool[:default] = Relaton::Logger::Log.new(io)
      end
      Relaton.logger_pool.info "info"
      Relaton.logger_pool.warn "warn"
      expect(io.string).to eq "INFO: info\nWARN: warn\n"
      Relaton.logger_pool.truncate
      expect(io.string).to eq ""
      Relaton.logger_pool.error "error"
      expect(io.string).to eq "ERROR: error\n"
    end
  end
end
