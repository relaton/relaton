# frozen_string_literal: true

require "graphql/client"
require "graphql/client/http"

Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8

module Relaton::Bsi
  # Scraper.
  module Scraper
    HTTP = GraphQL::Client::HTTP.new "https://shop-bsi.myshopify.com/api/2021-04/graphql.json" do
      def headers(_context)
        { "x-shopify-storefront-access-token": "c935c196c0b7d1d86bfb5139006cfd46" }
      end
    end

    Schema = GraphQL::Client.load_schema File.join(__dir__, "schema.json")

    Client = GraphQL::Client.new(schema: Schema, execute: HTTP)

    Product = Client.parse <<~'GRAPHQL'
      fragment ProductFragment on Product {
        createdAt
        publishedAt
        updatedAt
        productType
        committee: metafield(namespace: "global", key: "committee") {
          value
        }
        designated: metafield(namespace: "global", key: "designatedStandard") {
          value
        }
        packContents: metafield(namespace: "global", key: "packContents") {
          value
        }
        summary: metafield(namespace: "global", key: "summary") {
          value
        }
        corrigendumHandle: metafield(namespace: "global", key: "corrigendumHandle") {
          value
        }
        variants(first: 250) {
          edges {
            node {
              version: metafield(namespace: "global", key: "version") {
                value
              }
              isbn: metafield(namespace: "global", key: "isbn") {
                value
              }
            }
          }
        }
        description
      }
    GRAPHQL

    Query = Client.parse <<~GRAPHQL
      query GetProducts($h0: String!) {
        productByHandle(handle: $h0) {
          ...Relaton::Bsi::Scraper::Product::ProductFragment
        }
      }
    GRAPHQL

    class << self
      # Parse page.
      # @param hit [Relaton::Bsi::Hit]
      # @return [Relaton::Bsi::IetemData]
      def parse_page(hit) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        # doc = hit.hit_collection.agent.get hit.hit[:url]
        result = Client.query(Query::GetProducts, variables: { h0: hit.hit[:url] })
        data = result.data.product_by_handle.to_h
        item = Relaton::Bsi::ItemData.new(
          fetched: Date.today.to_s,
          type: "standard",
          docidentifier: fetch_docid(hit.hit[:code], data),
          docnumber: hit.hit[:code].match(/\d+/).to_s,
          language: ["en"],
          script: ["Latn"],
          title: fetch_titles(hit.hit[:title]),
          status: fetch_status(hit.hit[:status]),
          date: fetch_dates(hit),
          contributor: fetch_contributors(hit, data),
          abstract: fetch_abstract(data),
          copyright: fetch_copyright(hit),
          source: fetch_link(hit.hit[:url]),
          # relation: fetch_relations(doc),
          place: [Relaton::Bib::Place.new(city: "London")],
          ext: fetch_ext(hit, data),
        )
        item.create_id
        item
      end

      private

      def fetch_ext(hit, data)
        Ext.new(
          doctype: fetch_doctype(hit),
          flavor: "bsi",
          ics: fetch_ics(hit.hit[:ics]),
          structuredidentifier: fetch_structuredid(hit),
        )
      end

      # @param ics [Array<String>]
      # @return [Array<Relaton::Bib::ICS>]
      def fetch_ics(ics)
        ics.map do |s|
          code, = s.split
          Relaton::Bib::ICS.new(code: code, text: Isoics.fetch(code).description)
        end
      end

      # Fetch abstracts.
      # @param data [Hash]
      # @return [Array<Relaton::Bib::Abstract>]
      def fetch_abstract(data)
        return [] unless data["description"]

        [Relaton::Bib::Abstract.new(content: data["description"], language: "en", script: "Latn")]
      end

      # Fetch docid.
      # @param docid [String]
      # @param data [Hash]
      # @return [Array<Relaton::Bib::Docidentifier>]
      def fetch_docid(docid, data) # rubocop:disable Metrics/AbcSize
        ids = [{ type: "BSI", content: docid, primary: true }]
        if data.any? && data["variants"]["edges"][0]["node"]["isbn"]
          isbn = data["variants"]["edges"][0]["node"]["isbn"]["value"]
          ids << { type: "ISBN", content: isbn }
        end
        ids.map do |did|
          Relaton::Bsi::Docidentifier.new(**did)
        end
      end

      # Fetch status.
      # @param status [String]
      # @return [Relaton::Bib::Status, nil]
      def fetch_status(status)
        return unless status

        stage = Relaton::Bib::Status::Stage.new(content: status)
        Relaton::Bib::Status.new(stage: stage)
      end

      # @param hit [Relaton::Bsi::Hit]
      # @return [Relaton::Iso::StructuredIdentifier]
      def fetch_structuredid(hit)
        content, origyr = hit.hit[:code].split(":")
        project_number = Relaton::Iso::ProjectNumber.new(content: content, origyr: origyr)
        Relaton::Iso::StructuredIdentifier.new project_number: project_number
      end

      # Fetch relations.
      # @param doc [Mechanize::Page]
      # @return [Array<Hash>]
      # def fetch_relations(doc)
      #   doc.xpath("//tr[th='Replaces']/td/a").map do |r|
      #     fref = RelatonBib::FormattedRef.new(content: r.text, language: "en", script: "Latn")
      #     link = fetch_link r[:href]
      #     bibitem = BsiBibliographicItem.new(formattedref: fref, type: "standard", link: link)
      #     { type: "complements", bibitem: bibitem }
      #   end
      # end

      # Fetch titles.
      # @param title [String]
      # @return [Array<Relaton::Bib::Title>]
      def fetch_titles(title)
        titles = split_title(title).map do |t|
          Relaton::Bib::Title.new(**t, language: "en", script: "Latn")
        end
        titles << Relaton::Bib::Title.new(type: "main", content: title, language: "en", script: "Latn")
      end

      def split_title(title)
        ttls = title.split(/\s(?:-|\u2014)\s/) # if ttls.size == 1
        case ttls.size
        when 0, 1 then [{ type: "title-main",  content: ttls.first }]
        else intro_or_part ttls
        end
      end

      # @param ttls [Array<String>]
      # @return [Array<Hash>]
      def intro_or_part(ttls)
        titles = [{ type: "title-intro", content: ttls[0] }, { type: "title-main", content: ttls[1] }]
        parts = ttls.slice(2..-1)
        titles << { type: "title-part", content: parts.join(" -- ") } if parts.any?
        titles
      end

      #
      # Fetch doctype.
      #
      # @param [Relaton::Bsi::Hit] hit hit
      #
      # @return [Relaton::Bsi::Doctype] doctype
      #
      def fetch_doctype(hit)
        Doctype.new(content: doctype(hit))
      end

      def doctype(hit)
        case hit.hit[:code]
        when /(^|\s)Flex\s/ then "flex-standard"
        when /(^|\s)PAS\s/ then "publicly-available-specification"
        else hit.hit[:doctype]
        end
      end

      # Fetch dates
      # @param hit [Relaton::Bsi:Hit]
      # @return [Array<Relaton::Bib::Date>]
      def fetch_dates(hit)
        [Relaton::Bib::Date.new(type: "published", at: hit.hit[:date])]
      end

      # Fetch contributors
      # @param hit [Relaton::Bsi::Hit]
      # @param data [Hash]
      # @return [Array<Relaton::Bib::Contributor>]
      def fetch_contributors(hit, data)
        contribs = [create_contributor({ type: "publisher" }, owner_entity(hit))]

        wg = data["committee"]&.fetch("value")
        if wg
          subdivision = Relaton::Bib::Subdivision.new(
            type: "technical-committee",
            name: [Relaton::Bib::TypedLocalizedString.new(content: wg)],
          )
          org = bsi_org(subdivision: [subdivision])
          desc = Relaton::Bib::LocalizedMarkedUpString.new(content: "committee")
          role = Relaton::Bib::Contributor::Role.new(type: "author", description: [desc])
          contribs << Relaton::Bib::Contributor.new(role: [role], organization: org)
        end
        contribs
      end

      def create_contributor(role, org)
        role = Relaton::Bib::Contributor::Role.new(**role)
        Relaton::Bib::Contributor.new(role: [role], organization: org)
      end

      # Fetch links.
      # @param path [String]
      # @return [Array<Relaton::Bib::Uri>]
      def fetch_link(path)
        url = "#{HitCollection::DOMAIN}/products/#{path}"
        [Relaton::Bib::Uri.new(type: "src", content: url)]
      end

      # Fetch copyright.
      # @param hit [Relaton::Bsi::Hit]
      # @return [Array<Relaton::Bib::Copyright>]
      def fetch_copyright(hit)
        owner = Relaton::Bib::ContributionInfo.new organization: owner_entity(hit)
        from = Date.parse(hit.hit[:date]).year.to_s
        [Relaton::Bib::Copyright.new(owner: [owner], from: from)]
      end

      # @param hit [Relaton::Bsi::Hit]
      # @return [Relaton::Bib::Organization]
      def owner_entity(hit)
        case hit.hit[:publisher]
        when "BSI" then bsi_org
        else
          name = Relaton::Bib::TypedLocalizedString.new(content: hit.hit[:publisher])
          Relaton::Bib::Organization.new(name: [name])
        end
      end

      def bsi_org(subdivision: [])
        abbre = Relaton::Bib::LocalizedString.new(content: "BSI", language: "en", script: "Latn")
        name = Relaton::Bib::TypedLocalizedString.new(
          content: "British Standards Institution", language: "en", script: "Latn"
        )
        uri = Relaton::Bib::Uri.new(content: "https://www.bsigroup.com/")
        Relaton::Bib::Organization.new abbreviation: abbre, name: [name], uri: [uri], subdivision: subdivision
      end
    end
  end
end
