require "addressable/uri"
require_relative "model/item"

module Relaton
  module Calconnect
    module Scraper
      extend Core::HashKeysSymbolizer
      extend Core::ArrayWrapper

      DOMAIN = "https://standards.calconnect.org/".freeze
      SCHEME, HOST = DOMAIN.split(%r{:?/?/})
      # DOMAIN = "http://127.0.0.1:4000/".freeze

      class << self
        #
        # Parse document page
        #
        # @papam hit [Hash] document hash
        #
        # @return [Relaton::Calconnect::ItemData] bibliographic item
        #
        def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          hash = symbolize_hash_keys hit
          links = array(hash[:link])
          link = links.detect { |l| l[:type] == "rxl" }
          if link
            bib = fetch_bib_xml link[:content]
            update_links bib, links
          else
            hash.delete :fetched
            bib = hash_to_item hash
          end
          update_sources bib
          bib
        end

        private

        #
        # Fetch bibliographic item from XML source
        #
        # @param url [String] URL to fetch
        #
        # @return [RelatonCalconnect::CcBibliographicItem] bibliographic item
        #
        def fetch_bib_xml(url) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          rxl = get_rxl url
          uri_rxl = rxl.at("uri[@type='rxl']")
          if uri_rxl
            uri_xml = rxl.xpath("//uri").to_xml
            rxl = get_rxl uri_rxl.text
            docid = rxl.at "//docidentifier"
            docid.add_previous_sibling uri_xml
          end
          xml = rxl.to_xml.gsub(%r{(</?)technical-committee(>)}, '\1committee\2')
            .gsub(%r{type="(?:csd|CC)"(?=>)}i, '\0 primary="true"')
          Item.from_xml xml
        end

        # @param path [String]
        # @return [Nokogiri::XML::Document]
        def get_rxl(path)
          resp = Faraday.get DOMAIN + path
          Nokogiri::XML resp.body
        end

        #
        # Fix editorial group
        #
        # @param [Hash] doc
        #
        # @return [Hash]
        #
        def hash_to_item(hash)
          hash_to_title hash
          hash_to_source hash
          hash_to_docid hash
          hash_to_date hash
          hash_to_contributor hash
          hash_to_edition hash
          hash_to_version hash
          hosh_to_abstract hash
          hash_to_status hash
          hash_to_relation hash
          hash_to_copyrigh hash
          hash_to_keyword hash
          hash_to_ext hash
          ItemData.new(**hash)
        end

        def hash_to_title(hash)
          hash[:title] = array(hash[:title]).map do |t|
            t[:language] = t[:language].first if t[:language].is_a? Array
            t[:script] = t[:script].first if t[:script].is_a? Array
            t.delete :format
            Bib::Title.new(**t)
          end
        end

        def hash_to_source(hash)
          hash[:source] = array(hash[:link]).map { |link| Bib::Uri.new(type: "src", **link) }
        end

        def hash_to_docid(hash)
          docid = hash.delete(:docid)
          return unless docid

          docid_types = %w[CC CSD]
          hash[:docidentifier] = array(docid).map do |id|
            id[:primary] = true if docid_types.include? id[:type].upcase
            id[:content] = id.delete(:id) if id[:id]
            Bib::Docidentifier.new(**id)
          end
        end

        def hash_to_date(hash)
          hash[:date] = array(hash[:date]).map do |d|
            d[:at] = d.delete(:value) if d[:value]
            Bib::Date.new(**d)
          end
        end

        def hash_to_contributor(hash)
          hash[:contributor] = array(hash[:contributor]).map do |contrib|
            if contrib[:organization]
              contrib[:organization] = create_organization contrib[:organization]
            elsif contrib[:person]
              contrib[:person] = create_person contrib[:person]
            end
            contrib[:role] = array(contrib[:role]).map do |role|
              role[:description] = array(role[:description]).map do |desc|
                Bib::LocalizedMarkedUpString.new content: desc
              end
              Bib::Contributor::Role.new(**role)
            end
            Bib::Contributor.new(**contrib)
          end
        end

        def create_organization(org_hash)
          org_name = array(org_hash[:name]).each { |name| Bib::TypedLocalizedString.new(**name) }
          contact = create_contact org_hash[:contact]
          Bib::Organization.new(name: org_name, **contact)
        end

        def create_contact(contact_hash)
          array(contact_hash).each_with_object({address: [], email: [], uri: []}) do |cont, acc|
            case cont
            in { address: addr_hash }
              acc[:address] = Bib::Address.new(**addr_hash)
            in { email: email }
              acc[:email] << email
            in { uri: uri }
              acc[:uri] << Bib::Uri.new(content: uri)
            end
          end
        end

        def create_person(person_hash)
          completename = Bib::LocalizedString.new(**person_hash[:name][:completename])
          name = Bib::FullName.new completename: completename
          affiliation = array(person_hash[:affiliation]).map do |aff|
            org = create_organization aff[:organization]
            Bib::Affiliation.new(organization: org)
          end
          contact = create_contact person_hash[:contact]
          Bib::Person.new(name: name, affiliation: affiliation, **contact)
        end

        def hash_to_edition(hash)
          number = hash.dig(:edition, :content)
          hash[:edition] = Bib::Edition.new(number: number) if number
        end

        def hash_to_version(hash)
          hash[:version] = array(hash[:version]).map do |ver|
            Bib::Version.new(revision_date: ver[:revision_date])
          end
        end

        def hosh_to_abstract(hash)
          hash[:abstract] = array(hash[:abstract]).map do |abs|
            Bib::LocalizedMarkedUpString.new(**abs)
          end
        end

        def hash_to_status(hash)
          docstatus = hash.delete(:docstatus)
          return unless docstatus

          stage = Bib::Status::Stage.new content: docstatus.dig(:stage, :value)
          hash[:status] = Bib::Status.new stage: stage
        end

        def hash_to_relation(hash)
          hash[:relation] = array(hash[:relation]).map do |rel|
            Bib::Relation.new(type: rel[:type], bibitem: hash_to_item(rel[:bibitem]))
          end
        end

        def hash_to_copyrigh(hash)
          hash[:copyright] = array(hash[:copyright]).map do |cr|
            cr[:owner] = array(cr[:owner]).map do |owner|
              org_name = array(owner[:name]).map do |name|
                Bib::TypedLocalizedString.new(**name)
              end
              Bib::ContributionInfo.new organization: Bib::Organization.new(name: org_name)
            end
            Bib::Copyright.new(**cr)
          end
        end

        def hash_to_keyword(hash)
          hash[:keyword] = array(hash[:keyword]).map do |kw|
            taxon = Bib::LocalizedString.new(**kw)
            Bib::Keyword.new(taxon: taxon)
          end
        end

        def hash_to_ext(hash)
          return unless hash[:ext]

          hash_to_doctype hash[:ext]
          hash_to_editorialgroup hash
          hash[:ext] = Ext.new(flavor: "calconnect", **hash.delete(:ext))
        end

        def hash_to_doctype(ext)
          return unless ext[:doctype]

          ext[:doctype] = Doctype.new content: ext.dig(:doctype, :type), abbreviation: ext.dig(:doctype, :abbreviation)
        end

        def hash_to_editorialgroup(hash)
          editorialgroup = hash[:ext].delete(:editorialgroup)
          array(editorialgroup).each do |eg|
            subdiv_name = Bib::TypedLocalizedString.new content: eg[:name]
            subdivision = Bib::Subdivision.new(type: "technical-committee", name: [subdiv_name])
            org_name = Bib::TypedLocalizedString.new content: "CalConnect"
            org = Bib::Organization.new name: [org_name], subdivision: [subdivision]
            description = Bib::LocalizedMarkedUpString.new content: "committee"
            role = Bib::Contributor::Role.new type: "author", description: [description]
            hash[:contributor] ||= []
            hash[:contributor] << Bib::Contributor.new(organization: org, role: [role])
          end
        end

        def update_links(bib, links)
          links.each do |l|
            tu = l.transform_keys(&:to_sym)
            bib.source << Relaton::Bib::Uri.new(**tu) unless bib.source(l[:type])
          end
          bib
        end

        def update_sources(bib)
          bib.source.each do |l|
            uri = Addressable::URI.parse l.content
            l.content = uri.merge(scheme: SCHEME, host: HOST).to_s unless uri.host
          end
        end
      end
    end
  end
end
