require "date"
require "tmpdir"
require "shellwords"
require "parslet"
require "relaton/cli/relaton_file"
require "relaton/cli/xml_convertor"
require "relaton/cli/yaml_convertor"
require "relaton/cli/data_fetcher"
require "relaton/cli/index_site_generator"
require "relaton/cli/subcommand_collection"
require "relaton/cli/subcommand_db"
require "fcntl"

module Relaton
  module Cli
    class Command < Thor
      include Relaton::Cli
      class_before :relaton_config
      class_option :verbose, aliases: :v, type: :boolean, desc: "Output warnings"

      desc "version", "Show Relaton version"

      def version
        Relaton::Cli.version
      end

      desc "fetch CODE", "Fetch Relaton XML for Standard identifier CODE"
      option :type, aliases: :t,
                    desc: "Type of standard to get bibliographic entry for"
      option :format, aliases: :f,
                      desc: "Output format (xml, yaml, bibtex). Default xml."
      option :year, aliases: :y, type: :numeric, desc: "Year the standard was published"
      option :"all-parts", type: :boolean, desc: "Fetch all parts"
      option :"keep-year", type: :boolean,
                           desc: "Undated reference should return actual reference with year"
      option :retries, aliases: :r, type: :numeric,
                       desc: "Number of network retries. Default 1."
      option :"no-cache", type: :boolean, desc: "Ignore cache"
      option :"publication-date-before",
        desc: "Fetch only documents published before the specified date " \
          "(e.g. 2008, 2008-02, or 2008-02-02)"
      option :"publication-date-after",
        desc: "Fetch only documents published after the specified date " \
          "(e.g. 2002, 2002-01, or 2002-01-01)"

      def fetch(code)
        io = IO.new($stdout.fcntl(::Fcntl::F_DUPFD), mode: "w:UTF-8")
        io.puts(fetch_document(code, options) || supported_type_message)
      end

      desc "extract Metanorma-XML-File / Directory Relaton-XML-Directory",
           "Extract Relaton XML from Metanorma XML file / directory"
      option :extension, aliases: :x, default: "rxl", desc: "File extension of Relaton XML files, " \
                                                            "defaults to 'rxl'"

      def extract(source_dir, outdir)
        Relaton::Cli::RelatonFile.extract(source_dir, outdir, options)
      end

      desc "concatenate SOURCE-DIR COLLECTION-FILE",
           "Concatenate entries in DIRECTORY (containing Relaton-XML or YAML) into a Relaton Collection"
      option :title, aliases: :t,  desc: "Title of resulting Relaton collection"
      option :organization, aliases: :g, desc: "Organization owner of Relaton collection"
      option :extension, aliases: :x, desc: "File extension of destination " \
                                            "Relaton file, defaults to 'rxl'"

      def concatenate(source_dir, outfile)
        Relaton::Cli::RelatonFile.concatenate(source_dir, outfile, options)
      end

      desc "split Relaton-Collection-File Relaton-XML-Directory",
           "Split a Relaton Collection into multiple files"
      option :extension, aliases: :x, default: "rxl", desc: "File extension of Relaton XML files, " \
                                                            "defaults to 'rxl'"

      def split(source, outdir)
        Relaton::Cli::RelatonFile.split(source, outdir, options)
      end

      desc "yaml2xml YAML", "Convert Relaton YAML into Relaton Collection XML " \
                            "or separate files"
      option :extension, aliases: :x, default: "rxl", desc: "File extension of Relaton XML files, " \
                                                            "defaults to 'rxl'"
      option :prefix, aliases: :p, desc: "Filename prefix of individual " \
                                         "Relaton XML files, defaults to empty"
      option :outdir, aliases: :o, desc: "Output to the specified directory " \
                                         "with individual Relaton Bibdata XML files"
      option :require, aliases: :r, type: :array, desc: "Require LIBRARY " \
                                                        "prior to execution"
      option :overwrite, aliases: :f, type: :boolean, default: false,
                         desc: "Overwrite the existing file"

      def yaml2xml(filename)
        Relaton::Cli::YAMLConvertor.to_xml(filename, options)
      end

      desc "xml2yaml XML", "Convert Relaton XML into Relaton Bibdata / " \
                           "Bibcollection YAML (and separate files)"
      option :extension, aliases: :x, default: "yaml", desc: "File extension of Relaton YAML files, " \
                                                             "defaults to 'yaml'"
      option :prefix, aliases: :p, desc: "Filename prefix of Relaton XML " \
                                         "files, defaults to empty"
      option :outdir, aliases: :o, desc: "Output to the specified directory " \
                                         "with individual Relaton Bibdata YAML files"
      option :require, aliases: :r, type: :array, desc: "Require LIBRARY " \
                                                        "prior to execution"
      option :overwrite, aliases: :f, type: :boolean, default: false,
                         desc: "Overwrite the existing file"

      def xml2yaml(filename)
        Relaton::Cli::XMLConvertor.to_yaml(filename, options)
      end

      desc "xml2html RELATON-INDEX-XML", "Convert Relaton Collection XML into HTML"
      option :stylesheet, aliases: :s, desc: "Stylesheet file path for " \
                                             "rendering HTML index"
      option :templatedir, aliases: :t, desc: "Liquid template directory for " \
                                              "rendering Relaton items and collection"
      option :overwrite, aliases: :f, type: :boolean, default: false,
                         desc: "Overwrite the existing file"

      def xml2html(file, style = nil, template = nil)
        Relaton::Cli::XMLConvertor.to_html(file, style, template)
      end

      desc "yaml2html RELATON-INDEX-YAML", "Concatenate Relaton Collection " \
                                           "YAML into HTML"
      option :stylesheet, aliases: :s, desc: "Stylesheet file path for " \
                                             "rendering HTML index"
      option :templatedir, aliases: :t, desc: "Liquid template directory for " \
                                              "rendering Relaton items and collection"
      option :overwrite, aliases: :f, type: :boolean, default: false,
                         desc: "Overwrite the existing file"

      def yaml2html(file, style = nil, template = nil)
        Relaton::Cli::YAMLConvertor.to_html(file, style, template)
      end

      desc "index [DATA-DIR]",
           "Build a browsable HTML index site from a folder of Relaton YAML docs (default ./data)"
      option :output, aliases: :o, default: "_site",
                      desc: "Output directory for the generated site"
      option :flavor,
             desc: "Build from relaton/relaton-data-<flavor> (shallow-cloned) instead of a local folder"
      option :repo,
             desc: "Build from a GitHub repo ORG/NAME (shallow-cloned) instead of a local folder"
      option :branch, desc: "Branch to clone when --flavor/--repo is used"
      option :title, aliases: :t, desc: "Index page title"
      option :"base-url",
             desc: "Base URL for raw YAML links (defaults to the raw GitHub URL when cloning)"
      option :mode, aliases: :m, default: "embedded",
                    desc: "Data delivery mode: embedded, dom, or static-json"
      option :overwrite, aliases: :f, type: :boolean, default: true,
                         desc: "Overwrite existing output files"

      def index(data_dir = nil)
        with_index_source(data_dir) do |dir, default_base_url, default_title|
          Relaton::Cli::IndexSiteGenerator.generate(
            dir,
            output: options[:output],
            mode: options[:mode],
            title: options[:title] || default_title,
            base_url: options[:"base-url"] || default_base_url,
            overwrite: options[:overwrite],
          )
        end
      end

      desc "convert XML", "Convert Relaton XML document"
      option :format, aliases: :f, required: true, desc: "Output format (yaml, bibtex, asciibib)"
      option :output, aliases: :o, desc: "Output to the specified file"

      def convert(file) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
        xml = Nokogiri::XML(File.read(file, encoding: "UTF-8"))
        item = Relaton::Cli.parse_xml xml
        result = if /yaml|yml/.match?(options[:format])
                   item.to_yaml
                 else item.send "to_#{options[:format]}"
                 end
        ext = case options[:format]
              when "bibtex" then "bib"
              when "asciibib" then "adoc"
              else options[:format]
              end
        output = options[:output] || file.sub(/(?<=\.)[^.]+$/, ext)
        File.write output, result, encoding: "UTF-8"
      end

      desc "fetch-data SOURCE", "Fetch all the documents from a source"
      option :output, aliases: :o, desc: "Output dir. Default: ./data/"
      option :format, aliases: :f, desc: "Output format (yaml, xml, bibxml). Default: yaml"

      def fetch_data(source)
        DataFetcher.fetch source, options
      end

      desc "collection SUBCOMMAND", "Collection manipulations"
      subcommand "collection", SubcommandCollection

      desc "db SUBCOMMAND", "Cache DB manipulation"
      subcommand "db", SubcommandDb

      no_commands do
        def relaton_config
          Relaton::Logger.configure do |conf|
            if options[:verbose]
              conf.logger_pool[:default].add_level :info
            else
              conf.logger_pool[:default].remove_level :info
            end
          end
        end

        # Resolve the source folder for `index`. Locally it's just DATA-DIR
        # (default ./data). With --flavor/--repo it shallow-clones the GitHub
        # repo into a temp dir and yields its data/ subfolder plus sensible
        # defaults for the raw-YAML base URL and page title. The temp clone is
        # removed after the block returns.
        def with_index_source(data_dir)
          subdir = data_dir || "data"
          if options[:flavor] || options[:repo]
            repo = options[:repo] || "relaton/relaton-data-#{options[:flavor]}"
            flavor = options[:flavor] ||
              repo.split("/").last.sub(/\Arelaton-data-/, "")
            Dir.mktmpdir("relaton-index-") do |tmp|
              branch = clone_data_repo(repo, options[:branch], tmp)
              base = "https://raw.githubusercontent.com/#{repo}/#{branch}"
              yield File.join(tmp, subdir), base, "#{flavor.upcase} Index"
            end
          else
            yield subdir, nil, nil
          end
        end

        # Shallow-clone ORG/NAME into `dest`; return the checked-out branch name.
        def clone_data_repo(repo, branch, dest)
          url = "https://github.com/#{repo}.git"
          cmd = ["git", "clone", "--depth", "1", "--single-branch"]
          cmd += ["--branch", branch] if branch
          cmd += [url, dest]
          Relaton::Cli::Util.info "Cloning #{url}…"
          unless system(*cmd, out: File::NULL, err: File::NULL)
            raise Thor::Error,
                  "Failed to clone #{url}. Check the repo/branch name and that git is installed."
          end
          branch || `git -C #{Shellwords.escape(dest)} rev-parse --abbrev-ref HEAD`.strip
        end
      end
    end

    private

    DATE_FILTER_FORMAT = /\A\d{4}(-\d{2}(-\d{2})?)?\z/

    def parse_date_option(value, name)
      return unless value

      unless value.match?(DATE_FILTER_FORMAT)
        raise ArgumentError,
          "Invalid #{name}: #{value.inspect}. Expected YYYY, YYYY-MM, or YYYY-MM-DD."
      end
      parts = value.split("-").map(&:to_i)
      Date.new(*parts.concat([1] * (3 - parts.size)))
    rescue Date::Error
      raise ArgumentError,
        "Invalid #{name}: #{value.inspect}. Date components are out of range."
    end

    def validate_date_range(date_after, date_before)
      return unless date_after && date_before
      return if date_after < date_before

      raise ArgumentError,
        "Invalid date range: --publication-date-after (#{date_after}) must be before --publication-date-before (#{date_before})."
    end

    # @param code [String]
    # @param options [Hash]
    # @option options [String] :type
    # @option options [String, NilClass] :format
    # @option options [Integer, NilClass] :year
    # @return [String, nil]
    def fetch_document(code, options) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/AbcSize,Metrics/MethodLength
      year = options[:year]&.to_s
      dup_opts = options.dup.transform_keys { |k| k.to_s.gsub("-", "_").to_sym }
      %i[publication_date_before publication_date_after].each do |key|
        dup_opts[key] = parse_date_option(dup_opts[key], key.to_s.tr("_", "-").prepend("--")) if dup_opts[key]
      end
      validate_date_range dup_opts[:publication_date_after], dup_opts[:publication_date_before]
      if (processor = Relaton::Db::Registry.instance.by_type options[:type]&.upcase)
        doc = Relaton.db.fetch_std code, year, processor.short, **dup_opts
      elsif options[:type] then return
      else doc = Relaton.db.fetch(code, year, **dup_opts)
      end
      return "No matching bibliographic entry found" unless doc

      serialize doc, options[:format]
    rescue Parslet::ParseFailed
      %("#{code}" is not a recognized standards identifier)
    rescue Relaton::RequestError => e
      e.message
    end

    # @param doc [Relaton::Bib::ItemData]
    # @param format [String]
    # @return [String]
    def serialize(doc, format)
      case format
      when "yaml", "yml" then doc.to_yaml
      when "bibtex" then doc.to_bibtex
      else doc.to_xml bibdata: true
      end
    end

    def supported_type_message
      ["Recognised types:", registered_types.sort.join(", ")].join(" ")
    end

    def registered_types
      @registered_types ||=
        Relaton::Db::Registry.instance.processors.each.map { |_n, pr| pr.prefix }
    end
  end
end
