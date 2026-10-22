module Relaton
  module Iec
    # Fetches in-development projects from the IEC Harmonized API
    # (/harmonized/projects). The projects endpoint shares the OAuth app,
    # pagination and lastChangeTimestampFrom cursor with publications —
    # the credential's PROJ_PUBS name covers both — but carries the stage
    # lifecycle and project relations inline, so there is no webstore
    # round-trip.
    class ProjectFetcher < DataFetcher
      PROJECT_ENTRYPOINT = "https://api.iec.ch/harmonized/projects?size=100&sortBy=urn&page=".freeze
      PROJECT_LAST_CHANGE_FILE = "last_change_projects.txt".freeze

      def fetch(source = "iec-projects-latest")
        @all = source.end_with?("-all")
        # The wipe is the no-prune legacy path (see DataFetcher#fetch).
        FileUtils.rm_rf @output if @all && !@prune
        FileUtils.mkdir_p @output
        fetch_all
        save_last_change
        report_errors
      end

      private

      def entrypoint
        PROJECT_ENTRYPOINT
      end

      def last_change_file
        PROJECT_LAST_CHANGE_FILE
      end

      def list_key
        "project"
      end

      def fetch_pub(project)
        bib = ProjectParser.new(project, @errors).parse
        did = bib.docidentifier.detect(&:primary)
        file = unique_output_file(did.to_s)
        @files << file
        ts = project["lastChangeTimestamp"]
        @last_change_max = ts if ts && last_change_max < ts
        File.write file, to_yaml(bib), encoding: "UTF-8"
      end
    end
  end
end
