describe Relaton::Logger::Log do
  subject { described_class.new $stderr }

  context "initialize" do
    it "default" do
      expect(Logger::LogDevice).to receive(:new).with($stderr, shift_age: 0, shift_size: 1048576).and_return :dev

      expect(subject.level).to eq ::Logger::INFO
      expect(subject.levels.to_a).to eq [5, 4, 3, 2, 1]
      expect(subject.progname).to be_nil
      expect(subject.datetime_format).to be_nil
      expect(subject.formatter).to be_nil
      expect(subject.instance_variable_get(:@logdev)).to eq :dev
    end

    it "with options" do
      expect(Logger::LogDevice).to receive(:new).with(
        $stderr, shift_age: 1, shift_size: 1024, shift_period_suffix: "%Y-%m-%d", binmode: true
      ).and_return :dev

      formatter = double("formatter")
      expect(formatter).to receive(:is_a?).with(Class).and_return true
      expect(formatter).to receive(:new).and_return :formatter
      l = described_class.new($stderr, 1, 1024, levels: %i[info], progname: "progname", formatter: formatter,
                                                datetime_format: "%m/%d/%Y", binmode: true,
                                                shift_period_suffix: "%Y-%m-%d")

      expect(l.level).to eq ::Logger::INFO
      expect(l.progname).to eq "progname"
      expect(l.datetime_format).to eq "%m/%d/%Y"
      expect(l.formatter).to eq :formatter
      expect(l.instance_variable_get(:@logdev)).to eq :dev
    end
  end

  context "instance methods" do
    it "#unknown" do
      expect(subject).to receive(:add).with(::Logger::UNKNOWN, "msg", "prog", key: "val").and_return true
      subject.unknown "msg", "prog", key: "val"
    end

    it "#fatal" do
      expect(subject).to receive(:add).with(::Logger::FATAL, "msg", "prog", key: "val").and_return true
      subject.fatal "msg", "prog", key: "val"
    end

    it "#error" do
      expect(subject).to receive(:add).with(::Logger::ERROR, "msg", "prog", key: "val").and_return true
      subject.error "msg", "prog", key: "val"
    end

    it "#warn" do
      expect(subject).to receive(:add).with(::Logger::WARN, "msg", "prog", key: "val").and_return true
      subject.warn "msg", "prog", key: "val"
    end

    it "#info" do
      expect(subject).to receive(:add).with(::Logger::INFO, "msg", "prog", key: "val").and_return true
      subject.info "msg", "prog", key: "val"
    end

    it "#debug" do
      expect(subject).to receive(:add).with(::Logger::DEBUG, nil, nil, key: "val").and_return true
      subject.debug(key: "val") { "msg" }
    end

    context "#add" do
      context "don't log" do
        before do
          prog = double("progname")
          expect(prog).not_to receive(:nil?)
          subject.progname = prog
        end

        it "no logdev" do
          subject.instance_variable_set :@logdev, nil
          expect(subject.add(::Logger::UNKNOWN, "msg")).to be true
        end

        it "severity < level" do
          expect(subject.add(::Logger::DEBUG, "msg")).to be true
        end

        it "severity > level" do
          subject.levels = [:warn, :error, :fatal]
          expect(subject.add(::Logger::INFO, "msg")).to be true
        end
      end

      it "progname is nil" do
        expect(subject.instance_variable_get(:@logdev)).to receive(:write).with(
          "ANY: msg\n",
        )
        subject.add(::Logger::UNKNOWN, "msg")
      end

      it "progname is not nil" do
        subject.progname = "progname"
        expect(subject.instance_variable_get(:@logdev)).to receive(:write).with(
          "[progname] FATAL: msg\n",
        )
        subject.add(::Logger::FATAL, "msg")
      end

      # it "message is nil" do
      #   expect(subject.instance_variable_get(:@logdev)).to receive(:write).with(
      #     "ERROR: progname\n",
      #   )
      #   subject.add(::Logger::ERROR, nil, "progname")
      # end

      it "key given" do
        expect(subject.instance_variable_get(:@logdev)).to receive(:write).with(
          "[progname] WARN: (key) msg\n",
        )
        subject.add(::Logger::WARN, "msg", "progname", key: "key")
      end

      it "block given" do
        expect(subject.instance_variable_get(:@logdev)).to receive(:write).with(
          "[progname] INFO: msg\n",
        )
        subject.add(::Logger::INFO, nil, "progname") { "msg" }
      end
    end

    it "#add_level" do
      subject.add_level :debug
      expect(subject.levels.to_a).to eq [5, 4, 3, 2, 1, 0]
      expect(subject.level).to eq 0
    end

    it "#remove_level" do
      subject.remove_level :info
      expect(subject.levels.to_a).to eq [5, 4, 3, 2]
      expect(subject.level).to eq 2
    end

    it "#truncate" do
      dev = double("dev")
      expect(dev).to receive(:truncate)
      subject.instance_variable_set :@logdev, dev
      subject.truncate
    end

    context "use IO" do
      let(:io) { StringIO.new }
      subject { described_class.new io }

      it "unknown" do
        subject.unknown "msg", "progname"
        expect(io.string).to eq "[progname] ANY: msg\n"
      end
    end
  end
end
