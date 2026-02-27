module Relaton
  module Oasis
    # Common methods for document and part parsers.
    module DataParserUtils
      #
      # Parse contributor.
      #
      # @return [Array<Bib::Contributor>] contributors
      #
      def parse_contributor
        publisher_oasis + parse_authorizer +
          parse_editorialgroup_contributor +
          parse_chairs + parse_editors
      end

      def publisher_oasis
        org = Bib::Organization.new(
          name: [Bib::TypedLocalizedString.new(content: "OASIS")],
          uri: [Bib::Uri.new(type: "uri", content: "https://www.oasis-open.org/")],
        )
        role = [
          Bib::Contributor::Role.new(
            type: "authorizer",
            description: [Bib::LocalizedMarkedUpString.new(
              content: "Standards Development Organization",
            )],
          ),
          Bib::Contributor::Role.new(type: "publisher"),
        ]
        [Bib::Contributor.new(organization: org, role: role)]
      end

      def parse_editors_from_text
        return [] unless text

        text.match(/(?<=Edited\sby\s)[^.]+/).to_s
          .split(/,?\sand\s|,\s/).map do |c|
          role = [Bib::Contributor::Role.new(type: "editor")]
          Bib::Contributor.new(role: role, person: create_person(c))
        end
      end

      def page
        return @page if defined? @page

        if link_node && link_node[:href].match?(/\.html$/)
          agent = Mechanize.new
          agent.agent.allowed_error_codes = [404]
          resp = retry_page(link_node[:href], agent)
          @page = resp if resp && resp.code == "200"
        end
      end

      #
      # Retry to get page.
      #
      # @param [String] url page URL
      # @param [Mechanize] agent HTTP client
      # @param [Integer] retries number of retries
      #
      # @return [Mechanize::Page, nil] page or nil
      #
      def retry_page(url, agent, retries = 3)
        sleep 1 # to avoid 429 error
        agent.get url
      rescue Errno::ETIMEDOUT, Net::OpenTimeout => e
        retry if (retries -= 1).positive?
        Util.error "Failed to get page `#{url}`\n#{e.message}"
        nil
      end

      def parse_chairs
        return [] unless page

        xpath = "//p[preceding-sibling::p[starts-with(., 'Chair')]]" \
                "[following-sibling::p[starts-with(., 'Editor')]]"
        page.xpath(xpath).map do |p|
          create_contribution_info(p, "editor", ["Chair"])
        end
      end

      def parse_editors
        return parse_editors_from_text unless page

        xpath = "//p[contains(@class, 'Contributor')]" \
                "[preceding-sibling::p[starts-with(., 'Editor')]]" \
                "[following-sibling::p[contains(@class, 'Title')]]"
        page.xpath(xpath).map do |p|
          create_contribution_info(p, "editor")
        end
      end

      def create_contribution_info(person_node, type, description = [])
        name = person_node.text.match(/^[^(]+/).to_s.strip
        email, org = person_node.xpath ".//a[@href]"
        entity = create_person name, email, org
        desc = description.map { |d| Bib::LocalizedMarkedUpString.new(content: d) }
        role = Bib::Contributor::Role.new(type: type, description: desc)
        Bib::Contributor.new(role: [role], person: entity)
      end

      def create_person(name, email = nil, org = nil)
        forename, surname = name.split
        fn = Bib::FullNameType::Forename.new(content: forename, language: "en",
                                             script: "Latn")
        sn = Bib::LocalizedString.new(content: surname, language: "en",
                                      script: "Latn")
        fullname = Bib::FullName.new(surname: sn, forename: [fn])
        Bib::Person.new(name: fullname, email: person_email(email),
                        affiliation: person_affiliation(org))
      end

      def person_email(email)
        return [] unless email

        [email[:href].split(":")[1]]
      end

      def person_affiliation(org)
        return [] unless org

        org_name = org.text.gsub(/[\r\n]+/, " ")
        organization = Bib::Organization.new(
          name: [Bib::TypedLocalizedString.new(content: org_name)],
          uri: [Bib::Uri.new(type: "uri", content: org[:href])],
        )
        [Bib::Affiliation.new(organization: organization)]
      end

      #
      # Parse document identifier specification.
      #
      # @param [String] num document number
      #
      # @return [String] document identifier with specification if needed
      #
      def parse_spec(num)
        case text
        when /OASIS Project Specification (\d+)/ then "#{num}-PS#{$1}"
        when /Committee Specification (\d+)/ then "#{num}-CS#{$1}"
        else num
        end
      end

      #
      # Parse document identifier part.
      #
      # @param [String] docid document identifier
      #
      # @return [String] document identifier with part if needed
      #
      def parse_part(docid)
        return docid if docid.match?(/(?:Part|Pt)\d+/i)

        case title
        when /Part\s(\d+)/ then "#{docid}-Pt#{$1}"
        else docid
        end
      end

      #
      # Parse document identifier errata.
      #
      # @param [String] id document identifier
      #
      # @return [String] document identifier with errata if needed
      #
      def parse_errata(id)
        return id.sub("errata", "Errata") if id.match?(/errata\d+/i)

        case title
        when /Plus\sErrata\s(\d+)/ then "#{id}-plus-Errata#{$1}"
        when /Errata\s(\d+)/ then "#{id}-Errata#{$1}"
        else id
        end
      end

      #
      # Parse document identifier.
      #
      # @return [Array<Bib::Docidentifier>] document identifier
      #
      def parse_docid
        id = "OASIS #{parse_docnumber}"
        [Bib::Docidentifier.new(type: "OASIS", content: id, primary: true)]
      end

      #
      # Parse document type.
      #
      # @return [Doctype] document type
      #
      def parse_doctype
        type = case text
               when /OASIS Project Specification/, /Committee Specification/
                 "specification"
               when /Technical Memorandum/ then "memorandum"
               when /Technical Resolution/ then "resolution"
               else "standard"
               end
        Doctype.new(content: type)
      end

      #
      # Parse technology area.
      #
      # @return [Array<String>] technology areas
      #
      def parse_technology_area(node)
        xpath = "./summary/div/div" \
                "/ul[@class='technology-areas__list']/li/a"
        node.xpath(xpath).map do |ta|
          ta.text.strip.gsub(/\s/, "-")
            .sub("development", "Development")
        end
      end

      def create_ext
        Ext.new(
          doctype: parse_doctype,
          flavor: "oasis",
          technology_area: parse_technology_area,
        )
      end
    end
  end
end
