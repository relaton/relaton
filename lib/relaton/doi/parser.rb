module Relaton
  module Doi
    class Parser
      COUNTRIES = %w[USA].freeze

      TYPES = {
        "book-chapter" => "inbook",
        "book-part" => "inbook",
        "book-section" => "inbook",
        "book-series" => "book",
        "book-set" => "book",
        "book-track" => "inbook",
        "component" => "misc",
        "database" => "dataset",
        "dissertation" => "thesis",
        "edited-book" => "book",
        "grant" => "misc",
        "journal-article" => "article",
        "journal-issue" => "article",
        "journal-volume" => "journal",
        "monograph" => "book",
        "other" => "misc",
        "peer-review" => "article",
        "posted-content" => "dataset",
        "proceedings-article" => "inproceedings",
        "proceedings-series" => "proceedings",
        "reference-book" => "book",
        "reference-entry" => "inbook",
        "report-component" => "techreport",
        "report-series" => "techreport",
        "report" => "techreport",
      }.freeze

      REALATION_TYPES = {
        "is-cited-by" => "isCitedIn",
        "belongs-to" => "related",
        "is-child-of" => "includedIn",
        "is-expression-of" => "expressionOf",
        "has-expression" => "hasExpression",
        "is-manifestation-of" => "manifestationOf",
        "is-manuscript-of" => "draftOf",
        "has-manuscript" => "hasDraft",
        "is-preprint-of" => "draftOf",
        "has-preprint" => "hasDraft",
        "is-replaced-by" => "obsoletedBy",
        "replaces" => "obsoletes",
        "is-translation-of" => "translatedFrom",
        "has-translation" => "hasTranslation",
        "is-version-of" => "editionOf",
        "has-version" => "hasEdition",
        "is-based-on" => "updates",
        "is-basis-for" => "updatedBy",
        "is-comment-on" => "commentaryOf",
        "has-comment" => "hasCommentary",
        "is-continued-by" => "hasSuccessor",
        "continues" => "successorOf",
        "is-derived-from" => "derives",
        "has-derivation" => "derivedFrom",
        "is-documented-by" => "describedBy",
        "documents" => "describes",
        "is-part-of" => "partOf",
        "has-part" => "hasPart",
        "is-review-of" => "reviewOf",
        "has-review" => "hasReview",
        "references" => "cites",
        "is-referenced-by" => "isCitedIn",
        "requires" => "hasComplement",
        "is-required-by" => "complementOf",
        "is-supplement-to" => "complementOf",
        "is-supplemented-by" => "hasComplement",
      }.freeze

      ATTRS = %i[type fetched title docidentifier date source abstract contributor place
                 ext relation extent series medium].freeze

      CROSSREF_API_URL = "https://api.crossref.org/works?query=%{query}&filter=%{filter}".freeze
      MAX_RETRIES = 3

      #
      # Initialize instance.
      #
      # @param [Hash] src The source hash.
      #
      def initialize(src)
        @src = src
        @item = {}
      end

      #
      # Initialize instance and parse the source hash.
      #
      # @param [Hash] src The source hash.
      #
      # @return [Bib::ItemData] The bibitem.
      #
      def self.parse(src)
        new(src).parse
      end

      #
      # Parse the source hash.
      #
      # @return [Bib::ItemData] The bibitem.
      #
      def parse
        ATTRS.each { |m| @item[m] = send "parse_#{m}" }
        create_bibitem @src["DOI"], @item
      end

      #
      # Create a bibitem from the bibitem hash.
      #
      # @param [String] doi The DOI.
      # @param [Hash] bibitem The bibitem hash.
      #
      # @return [Bib::ItemData] The bibitem.
      #
      def create_bibitem(doi, bibitem) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/MethodLength
        doctype_content = @src["type"]
        case doi
        when /\/nist/
          bibitem[:ext] = Nist::Ext.new(doctype: Nist::Doctype.new(content: doctype_content))
          Nist::ItemData.new(**bibitem)
        when /\/rfc\d+/
          bibitem[:ext] = Ietf::Ext.new(doctype: Ietf::Doctype.new(content: doctype_content))
          Ietf::ItemData.new(**bibitem)
        when /\/0026-1394\//
          bibitem[:ext] = Bipm::Ext.new(doctype: Bipm::Doctype.new(content: doctype_content))
          Bipm::ItemData.new(**bibitem)
        when /\/ieee/
          bibitem[:ext] = Ieee::Ext.new(doctype: Ieee::Doctype.new(content: doctype_content))
          Ieee::ItemData.new(**bibitem)
        else Bib::ItemData.new(**bibitem)
        end
      end

      #
      # Parse the type.
      #
      # @return [String] The type.
      #
      def parse_type
        TYPES[@src["type"]] || @src["type"]
      end

      #
      # Parse the ext element with doctype.
      #
      # @return [Bib::Ext] The ext element.
      #
      def parse_ext
        Bib::Ext.new doctype: Bib::Doctype.new(content: @src["type"])
      end

      #
      # Parse the fetched date.
      #
      # @return [String] The fetched date.
      #
      def parse_fetched
        Date.today.to_s
      end

      #
      # Parse titles from the source hash.
      #
      # @return [Array<Bib::Title>] The titles.
      #
      def parse_title # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        if @src["title"].is_a?(Array) && @src["title"].any?
          main_sub_titles
        elsif @src["project"].is_a?(Array) && @src["project"].any?
          project_titles
        elsif @src["container-title"].is_a?(Array) && @src["container-title"].size > 1
          @src["container-title"][0..-2].map { |t| create_title t }
        else []
        end
      end

      #
      # Parse main and subtitle from the source hash.
      #
      # @return [Array<Bib::Title>] The titles.
      #
      def main_sub_titles
        title = @src["title"].map { |t| create_title t }
        Array(@src["subtitle"]).each { |t| title << create_title(t, "subtitle") }
        Array(@src["short-title"]).each { |t| title << create_title(t, "short") }
        title
      end

      #
      # Fetch titles from the projects.
      #
      # @return [Array<Bib::Title>] The titles.
      #
      def project_titles
        Array(@src["project"]).reduce([]) do |memo, proj|
          memo + Array(proj["project-title"]).map { |t| create_title t["title"] }
        end
      end

      #
      # Create a title from the title and type.
      #
      # @param [String] title The title content.
      # @param [String] type The title type. Defaults to "main".
      #
      # @return [Bib::Title] The title.
      #
      def create_title(title, type = "main")
        cnt = str_cleanup CGI.unescapeHTML(title)
        Bib::Title.new type: type, content: cnt, script: "Latn"
      end

      #
      # Parse a docidentifier from the source hash.
      #
      # @return [Array<Bib::Docidentifier>] The docidentifier.
      #
      def parse_docidentifier
        %w[DOI ISBN ISSN].each_with_object([]) do |type, obj|
          prm = type == "DOI"
          Array(@src[type]).each do |id|
            t = issn_type(type, id)
            obj << Bib::Docidentifier.new(type: t, content: id, primary: prm)
          end
        end
      end

      #
      # Create an ISSN type if it's an ISSN ID.
      #
      # @param [String] type identifier type
      # @param [String] id identifier
      #
      # @return [String] identifier type
      #
      def issn_type(type, id)
        return type unless type == "ISSN"

        t = @src["issn-type"]&.find { |it| it["value"] == id }&.dig("type")
        t ? "issn.#{t}" : type.downcase
      end

      #
      # Parce dates from the source hash.
      #
      # @return [Array<Bib::Date>] The dates.
      #
      def parse_date # rubocop:disable Metrics/CyclomaticComplexity
        dates = %w[issued published approved].each_with_object([]) do |type, obj|
          next unless @src.dig(type, "date-parts")&.first&.compact&.any?

          obj << Bib::Date.new(type: type, at: date_type(type))
        end
        if dates.none?
          dates << Bib::Date.new(type: "created", at: date_type("created"))
        end
        dates
      end

      #
      # Join date parts into a string.
      #
      # @param [String] type The date type.
      #
      # @return [String] The date string.
      #
      def date_type(type)
        @src[type]["date-parts"][0].map { |d| d.to_s.rjust(2, "0") }.join "-"
      end

      #
      # Parse source URIs from the source hash.
      #
      # @return [Array<Bib::Uri>] The source URIs.
      #
      def parse_source # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity
        disprefered_links = %w[similarity-checking text-mining]
        links = []
        if @src["URL"]
          links << Bib::Uri.new(type: "DOI", content: @src["URL"])
        end
        [@src["link"], @src.dig("resource", "primary")].flatten.compact.each do |l|
          next if disprefered_links.include? l["intended-application"]

          type =  case l["URL"]
                  when /\.pdf$/ then "pdf"
                  # when /\/rfc\d+$|iopscience\.iop\.org|ieeexplore\.ieee\.org/
                  else "src"
                  end
          links << Bib::Uri.new(type: type, content: l["URL"]) # if type
        end
        links
      end

      #
      # Parse abstract from the source hash.
      #
      # @return [Array<Bib::LocalizedMarkedUpString>] The abstract.
      #
      def parse_abstract
        return [] unless @src["abstract"]

        content = @src["abstract"]
        abstract = Bib::Abstract.new(
          content: content, language: "en", script: "Latn",
        )
        [abstract]
      end

      #
      # Parse contributors from the source hash.
      #
      # @return [Array<Bib::Contributor>] The contributors.
      #
      def parse_contributor
        contribs = author_investigators
        contribs += authors_editors_translators
        contribs += contribs_from_parent(contribs)
        contribs << contributor(org_publisher, "publisher")
        contribs += org_aurhorizer
        contribs + org_enabler
      end

      #
      # Create authors investigators from the source hash.
      #
      # @return [Array<Bib::Contributor>] The authors investigators.
      #
      def author_investigators
        Array(@src["project"]).reduce([]) do |memo, proj|
          memo + create_investigators(proj, "lead-investigator") +
            create_investigators(proj, "investigator")
        end
      end

      #
      # Create investigators from the project.
      #
      # @param [Hash] project The project hash.
      # @param [String] type The investigator type. "lead-investigator" or "investigator".
      #
      # @return [Array<Bib::Contributor>] The investigators.
      #
      def create_investigators(project, type)
        description = type.gsub("-", " ")
        Array(project[type]).map do |inv|
          contributor(create_person(inv), "author", description)
        end
      end

      #
      # Create authors editors translators from the source hash.
      #
      # @return [Array<Bib::Contributor>] The authors editors translators.
      #
      def authors_editors_translators
        %w[author editor translator].each_with_object([]) do |type, a|
          @src[type]&.each do |c|
            contrib = if c["family"]
                        create_person(c)
                      else
                        create_org(str_cleanup(c["name"]))
                      end
            a << contributor(contrib, type)
          end
        end
      end

      #
      # Fetch authors and editors from parent if they are not present in the book part.
      #
      # @param [Array<Bib::Contributor>] contribs present contributors
      #
      # @return [Array<Bib::Contributor>] contributors with authors and editors from parent
      #
      def contribs_from_parent(contribs) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        return [] unless %w[inbook inproceedings dataset].include?(parse_type) && @src["container-title"]

        has_authors = contribs.any? { |c| c.role&.any? { |r| r.type == "author" } }
        has_editors = contribs.any? { |c| c.role&.any? { |r| r.type == "editor" } }
        return [] if has_authors && has_editors

        create_authors_editors(has_authors, "author")
      end

      #
      # Fetch parent item from Crossref.
      #
      # @return [Hash, nil] parent item
      #
      def parent_item
        @parent_item ||= begin
          query = CGI.escape [@src["container-title"][0], fetch_year].compact.join("+")
          filter = "type:#{%w[book book-set edited-book monograph reference-book].join ',type:'}"
          items = fetch_crossref(query: query, filter: filter)
          items&.detect { |i| i["title"].include? @src["container-title"][0] }
        end
      end

      #
      # Create authors and editors from parent item.
      #
      # @param [Boolean] has true if authors or editors are present in the book part
      # @param [String] type "author" or "editor"
      #
      # @return [Array<Bib::Contributor>] authors or editors
      #
      def create_authors_editors(has, type)
        return [] if has || !parent_item

        Array(parent_item[type]).map { |a| contributor(create_person(a), type) }
      end

      #
      # Cerate an organization publisher from the source hash.
      #
      # @return [Bib::Organization] The organization.
      #
      def org_publisher
        pbr = @src["institution"]&.detect do |i|
          @src["publisher"].include?(i["name"]) ||
            i["name"].include?(@src["publisher"])
        end
        a = pbr["acronym"]&.first if pbr
        create_org(str_cleanup(@src["publisher"]), a)
      end

      #
      # Clean up trailing punctuation and whitespace from a string.
      #
      # @param [String] str The string to clean up.
      #
      # @return [String] The cleaned up string.
      #
      def str_cleanup(str)
        str.strip.sub(/[,\/\s]+$/, "").sub(/\s:$/, "")
      end

      #
      # Create an organization with properly typed name and abbreviation.
      #
      # @param [String] name The organization name.
      # @param [String, nil] abbreviation The organization abbreviation.
      #
      # @return [Bib::Organization] The organization.
      #
      def create_org(name, abbreviation = nil)
        n = [Bib::TypedLocalizedString.new(content: name)]
        a = abbreviation ? Bib::LocalizedString.new(content: abbreviation) : nil
        Bib::Organization.new name: n, abbreviation: a
      end

      #
      # Parse authorizer contributor from the source hash.
      #
      # @return [Array<Bib::Contributor>] The authorizer contributor.
      #
      def org_aurhorizer
        return [] unless @src["standards-body"]

        name, acronym = @src["standards-body"].values_at("name", "acronym")
        org = create_org(
          CGI.unescapeHTML(name),
          acronym && CGI.unescapeHTML(acronym),
        )
        [contributor(org, "authorizer")]
      end

      #
      # Parse enabler contributor from the source hash.
      #
      # @return [Array<Bib::Contributor>] The enabler contributor.
      #
      def org_enabler
        Array(@src["project"]).each_with_object([]) do |proj, memo|
          proj["funding"].each do |f|
            memo << create_enabler(f.dig("funder", "name"))
          end
        end + Array(@src["funder"]).map { |f| create_enabler f["name"] }
      end

      #
      # Create enabler contributor with type "enabler".
      #
      # @param [String] name The funder name.
      #
      # @return [Bib::Contributor] The enabler contributor.
      #
      def create_enabler(name)
        contributor(create_org(name), "enabler")
      end

      #
      # Create contributor from an entity and a role type.
      #
      # @param [Bib::Person, Bib::Organization] entity The entity.
      # @param [String] type The role type.
      #
      # @return [Bib::Contributor] The contributor.
      #
      def contributor(entity, type, descriprion = nil)
        desc = descriprion ? [Bib::LocalizedMarkedUpString.new(content: descriprion)] : nil
        role = [Bib::Contributor::Role.new(type: type, description: desc)]
        if entity.is_a?(Bib::Person)
          Bib::Contributor.new(role: role, person: entity)
        else
          Bib::Contributor.new(role: role, organization: entity)
        end
      end

      #
      # Create a person from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Bib::Person] The person.
      #
      def create_person(person)
        Bib::Person.new(
          name: create_person_name(person),
          affiliation: create_affiliation(person),
          identifier: person_id(person),
        )
      end

      #
      # Create person affiliations from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Array<Bib::Affiliation>] The affiliations.
      #
      def create_affiliation(person)
        (person["affiliation"] || []).map do |a|
          Bib::Affiliation.new organization: create_org(a["name"])
        end
      end

      #
      # Create a person full name from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Bib::FullName] The full name.
      #
      def create_person_name(person)
        surname = titlecase(person["family"])
        sn = Bib::LocalizedString.new(content: surname, language: "en", script: "Latn")
        Bib::FullName.new(
          surname: sn, forename: forename(person), addition: nameaddition(person),
          completename: completename(person), prefix: nameprefix(person)
        )
      end

      #
      # Capitalize the first letter of each word in a string except for words that
      #   are 2 letters or less.
      #
      # @param [<Type>] str <description>
      #
      # @return [<Type>] <description>
      #
      def titlecase(str)
        str.split.map do |s|
          if s.size > 2 && s.upcase == s && !/\.&/.match?(s)
            s.capitalize
          else
            s
          end
        end.join " "
      end

      #
      # Create a person name prefix from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Array<Bib::LocalizedString>] The name prefix.
      #
      def nameprefix(person)
        return [] unless person["prefix"]

        [Bib::LocalizedString.new(content: person["prefix"], language: "en", script: "Latn")]
      end

      #
      # Create a complete name from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Bib::LocalizedString] The complete name.
      #
      def completename(person)
        return unless person["name"]

        Bib::LocalizedString.new(content: person["name"], language: "en", script: "Latn")
      end

      #
      # Create a forename from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Array<Bib::FullNameType::Forename>] The forename.
      #
      def forename(person)
        return [] unless person["given"]

        fname = titlecase(person["given"])
        [Bib::FullNameType::Forename.new(content: fname, language: "en", script: "Latn")]
      end

      #
      # Create an addition from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Array<Bib::LocalizedString>] The addition.
      #
      def nameaddition(person)
        return [] unless person["suffix"]

        [Bib::LocalizedString.new(content: person["suffix"], language: "en", script: "Latn")]
      end

      #
      # Create a person identifier from a person hash.
      #
      # @param [Hash] person The person hash.
      #
      # @return [Array<Bib::Person::Identifier>] The person identifier.
      #
      def person_id(person)
        return [] unless person["ORCID"]

        [Bib::Person::Identifier.new(type: "orcid", content: person["ORCID"])]
      end

      #
      # Parse a place from the source hash.
      #
      # @return [Array<Bib::Place>] The place.
      #
      def parse_place # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
        pub_location = @src["publisher-location"] || fetch_location
        return [] unless pub_location

        pls1, pls2 = pub_location.split(", ")
        pls1 = str_cleanup pls1
        pls2 &&= str_cleanup pls2
        if COUNTRIES.include? pls2
          country = Bib::Place::RegionType.new(content: pls2)
          [Bib::Place.new(city: pls1, country: [country])]
        elsif pls2 && pls2 == pls2&.upcase
          region = Bib::Place::RegionType.new(content: pls2)
          [Bib::Place.new(city: pls1, region: [region])]
        elsif pls1 == pls2 || pls2.nil? || pls2.empty?
          [Bib::Place.new(city: pls1)]
        else
          [Bib::Place.new(city: pls1), Bib::Place.new(city: pls2)]
        end
      end

      #
      # Fetch location from container.
      #
      # @return [String, nil] The location.
      #
      def fetch_location
        title = @item[:title].first&.content
        qparts = [title, fetch_year, @src["publisher"]]
        query = CGI.escape qparts.compact.join("+").gsub(" ", "+")
        filter = "type:#{%w[book-chapter book-part book-section book-track].join(',type:')}"
        items = fetch_crossref(query: query, filter: filter)
        items&.detect do |i|
          i["publisher-location"] && i["container-title"].include?(title)
        end&.dig("publisher-location")
      end

      #
      # Parse relations from the source hash.
      #
      # @return [Array<Bib::Relation>] The relations.
      #
      def parse_relation # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        rels = included_in_relation
        @src["relation"].each_with_object(rels) do |(k, v), a|
          type, desc = relation_type k
          Array(v).each do |r|
            rel_item = Crossref.get_by_id r["id"]
            title = rel_item["title"].map { |t| create_title t }
            docid = Bib::Docidentifier.new(content: r["id"], type: "DOI")
            bib = create_bibitem r["id"], title: title, docidentifier: [docid]
            a << Bib::Relation.new(type: type, description: desc, bibitem: bib)
          end
        end
      end

      #
      # Transform crossref relation type to relaton relation type.
      #
      # @param [String] crtype The crossref relation type.
      #
      # @return [Array<String>] The relaton relation type and description.
      #
      def relation_type(crtype)
        type = REALATION_TYPES[crtype] || begin
          desc = Bib::LocalizedMarkedUpString.new(content: crtype)
          "related"
        end
        [type, desc]
      end

      #
      # Create included in relation.
      #
      # @return [Array<Bib::Relation>] The relations.
      #
      def included_in_relation
        types = %w[
          book book-chapter book-part book-section book-track dataset journal-issue
          journal-value proceedings-article reference-entry report-component
        ]
        return [] unless @src["container-title"] && types.include?(@src["type"])

        @src["container-title"].map do |ct|
          contrib = create_authors_editors false, "editor"
          bib = Bib::ItemBase.new(title: [Bib::Title.new(content: ct)], contributor: contrib)
          Bib::Relation.new(type: "includedIn", bibitem: bib)
        end
      end

      #
      # Fetch year from the source hash.
      #
      # @return [String] The year.
      #
      def fetch_year
        d = @src["published"] || @src["approved"] || @src["created"]
        d["date-parts"][0][0]
      end

      #
      # Parse an extent from the source hash.
      #
      # @return [Array<Bib::Extent>] The extent.
      #
      def parse_extent # rubocop:disable Metrics/AbcSize
        extent = []
        extent << Bib::Locality.new(type: "volume", reference_from: @src["volume"]) if @src["volume"]
        extent << Bib::Locality.new(type: "issue", reference_from: @src["issue"]) if @src["issue"]
        if @src["page"]
          from, to = @src["page"].split("-")
          extent << Bib::Locality.new(type: "page", reference_from: from, reference_to: to)
        end
        extent.any? ? [Bib::Extent.new(locality: extent)] : []
      end

      #
      # Parse a series from the source hash.
      #
      # @return [Array<Bib::Series>] The series.
      #
      def parse_series # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        types = %w[inbook incollection inproceedings]
        return [] if !@src["container-title"] || types.include?(@item[:type]) || @src["type"] == "report-component"

        con_ttl = if main_sub_titles.any? || project_titles.any?
                    @src["container-title"]
                  elsif @src["container-title"].size > 1
                    sct = @src["short-container-title"]&.last
                    abbrev = Bib::LocalizedString.new(content: sct) if sct
                    @src["container-title"][-1..-1]
                  else []
                  end
        con_ttl.map do |ct|
          title = Bib::Title.new content: ct
          Bib::Series.new title: [title], abbreviation: abbrev
        end
      end

      #
      # Parse a medium from the source hash.
      #
      # @return [Bib::Medium, nil] The medium.
      #
      def parse_medium
        genre = @src["degree"]&.first
        return unless genre

        Bib::Medium.new genre: genre
      end

      #
      # Fetch data from Crossref API with retry logic.
      #
      # @param [String] query The query string.
      # @param [String] filter The filter string.
      #
      # @return [Array<Hash>, nil] Items array from response or nil for 4xx responses.
      #
      # @raise [Relaton::RequestError] If request fails after retries.
      #
      def fetch_crossref(query:, filter:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
        url = format(CROSSREF_API_URL, query: query, filter: filter)
        retries = 0
        begin
          resp = Crossref.agent.get url
          JSON.parse(resp.body).dig("message", "items")
        rescue Mechanize::ResponseCodeError => e
          return nil if e.response_code.start_with?("4")

          raise Relaton::RequestError, "Crossref request failed: #{e.response_code} #{e.page.body}"
        rescue Net::HTTP::Persistent::Error, Net::HTTPError, Errno::ECONNREFUSED => e
          retries += 1
          retry if retries <= MAX_RETRIES
          raise Relaton::RequestError, "Crossref network error after #{MAX_RETRIES} retries: #{e.message}"
        rescue JSON::ParserError => e
          raise Relaton::RequestError, "Crossref JSON parsing error: #{e.message}"
        end
      end
    end
  end
end
