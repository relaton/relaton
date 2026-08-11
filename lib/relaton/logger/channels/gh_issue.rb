require "net/http"
require "json"

module Relaton
  module Logger
    module Channels
      #
      # This class is used to report the log content as a GitHub issue in the
      # repository specified in the initializer.
      # The log content is stored in the issue body. Only unique log messages
      # are stored. When an open issue with the same title already exists, the
      # log is added to it as a comment rather than opening a duplicate.
      # Token is required to create an issue. It should be stored in the
      # environment variable GITHUB_TOKEN.
      # To create an issue, call the create_issue method after all log messages
      # are written.
      #
      class GhIssue
        #
        # Create a new instance of the class.
        #
        # @param [String] repo owner/repo name
        # @param [String] title title of the issue
        #
        def initialize(repo, title)
          @repo = repo
          @title = title
          @log = Set.new
          puts "GITHUB_TOKEN is not set!" if ENV["GITHUB_TOKEN"].nil?
        end

        def write(string)
          @log << string
        end

        def close
        end

        # Report the collected log. A crawler runs on a schedule, so creating a
        # fresh issue every time would pile up duplicates of the same standing
        # report; when an open issue with this title already exists, add the run's
        # log as a comment on it instead.
        def create_issue
          return if @log.empty? || ENV["GITHUB_TOKEN"].nil?

          if (number = open_issue_number)
            report_response post_comment(number), "Issue #{number} commented!", 201
          else
            report_response post_issue, "Issue created!", 201
          end
        end

        private

        def report_response(responce, success_message, success_code)
          if responce.code.to_i == success_code
            puts success_message
          else
            puts "Failed to report issue: #{responce.code} #{responce.message}\n#{responce.body}"
          end
        end

        # Number of the open issue with exactly this title, or nil. Any failure
        # (network, rate limit, missing search scope) degrades to nil, so the
        # worst case is the previous behaviour — a new issue.
        def open_issue_number
          query = "repo:#{@repo} is:issue is:open in:title \"#{@title}\""
          uri = URI("https://api.github.com/search/issues")
          uri.query = URI.encode_www_form(q: query, per_page: 100)
          responce = get(uri)
          return nil unless responce.code.to_i == 200

          items = JSON.parse(responce.body)["items"] || []
          items.find { |i| i["title"] == @title }&.fetch("number", nil)
        rescue StandardError => e
          puts "Failed to search for an open `#{@title}` issue: #{e.message}"
          nil
        end

        def get(uri)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.request(Net::HTTP::Get.new(uri.request_uri, headers))
        end

        def post(uri, body)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = body.to_json

          http.request(request)
        end

        def post_issue
          post URI("https://api.github.com/repos/#{@repo}/issues"), issue_body
        end

        def post_comment(number)
          post URI("https://api.github.com/repos/#{@repo}/issues/#{number}/comments"),
               { body: @log.join("\n") }
        end

        def issue_body
          { title: @title, body: @log.join("\n") }
        end

        def headers
          {
            "Content-Type" => "application/json",
            "Accept" => "application/vnd.github+json",
            "Authorization" => "Bearer #{ENV['GITHUB_TOKEN']}",
            "X-GitHub-Api-Version" => "2022-11-28",
          }
        end
      end
    end
  end
end
