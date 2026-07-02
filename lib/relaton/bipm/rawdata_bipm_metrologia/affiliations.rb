module Relaton::Bipm
  module RawdataBipmMetrologia
    class Affiliations
      attr_reader :affiliations

      #
      # Initialize parser
      #
      # @param [Array<Relaton::Bib::Affiliation>] affiliations directory with affiliations
      #
      def initialize(affiliations)
        @affiliations = affiliations
      end

      #
      # Parse affiliations
      #
      # @return [Relaton::Bipm::RawdataBipmMetrologia::Affiliations] affiliations
      #
      def self.parse(dir)
        affiliations = Dir["#{dir}/*.xml"].each_with_object([]) do |path, m|
          doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
          doc.xpath("//aff").each do |aff|
            m << parse_affiliation(aff) if aff.at("institution")
          end
        end.uniq { |a| a.organization.name.first.content }
        new affiliations
      end

      #
      # Parse affiliation organization
      # https://github.com/relaton/relaton-data-bipm/issues/17#issuecomment-1367035444
      #
      # @param [Nokogiri::XML::Element] aff
      #
      # @return [Relaton::Bib::Affiliation] Organization name, country, division, street address
      #
      def self.parse_affiliation(aff)
        text = aff.at("text()").text
        return if text.include? "Permanent address:" || text.include?("1005 Southover Lane") ||
          text == "Germany" || text.starts_with?("Guest") || text.starts_with?("Deceased") ||
          text.include?("Author to whom any correspondence should be addressed")

        args = {}
        institution = aff.at('institution')
        if institution
          name = institution.text
          return if name == "1005 Southover Lane"

          args[:subdivision] = parse_division(aff)
          args[:contact] = parse_address(aff)
        else
        #   div, name, city, country = aff.xpath("text()").text.strip.split(", ")
        #   div, name = name, div if name.nil?
        #   args[:subdivision] = [Relaton::Bib::LocalizedString.new(div)] if div
        #   args[:contact] = [Relaton::Bib::Address.new(city: city, country: country)] if city && country
          name = aff.text
        end
        args[:name] = [Relaton::Bib::LocalizedString.new(name)]
        org = Relaton::Bib::Organization.new(**args)
        Relaton::Bib::Affiliation.new(organization: org)
      end

      def self.parse_division(aff)
        div = aff.xpath("text()[following-sibling::institution]").text.gsub(/^\W*|\W*$/, "")
        return [] if div.empty?

        [Relaton::Bib::LocalizedString.new(div)]
      end

      def self.parse_address(aff)
        address = []
        addr = aff.xpath("text()[preceding-sibling::institution]").text.gsub(/^\W*|\W*$/, "")
        address << addr unless addr.empty?
        country = aff.at('country')
        address << country.text if country && !country.text.empty?
        address = address.join(", ")
        return [] if address.empty?

        [Relaton::Bib::Address.new(formatted_address: address)]
      end

      def self.parse_elements(aff)
        elements = aff.xpath("text()").text.strip.split(", ")
        case elements.size
        when 1 then { name: Relaton::Bib::LocalizedString.new(elements[0]) }
        when 2
          # name, country
          { name: Relaton::Bib::LocalizedString.new(elements[0]),
            contact: [Relaton::Bib::Address.new(formatted_address: elements[1])] }
        when 3
          # it can be name, country, city or name, city, country
          # so use formatted_address instead of city and country
          { name: Relaton::Bib::LocalizedString.new(elements[0]),
            contact: Relaton::Bib::Address.new(formatted_address: elements[1, 2].join(", ")) }
        end
      end

      #
      # Find affiliation by organization name
      #
      # @param [Strign] text string with organization name in it
      #
      # @return [Relaton::Bib::Affiliation]
      #
      def find(text)
        @affiliations.select { |a| text.include?(a.organization.name[0].content) }.sort.last
      end
    end
  end
end
