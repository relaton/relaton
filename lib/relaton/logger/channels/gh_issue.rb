require "net/http"

module Relaton
  module Logger
    module Channels
      #
      # This class is used to create a GitHub issue with the log content.
      # The issue will be created in the repository specified in the
      # initializer.
      # The log content is stored in the issue body. Only unique log messages
      # are stored.
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

        def create_issue
          return if @log.empty? || ENV["GITHUB_TOKEN"].nil?

          responce = post_issue

          if responce.code.to_i == 201
            puts "Issue created!"
          else
            puts "Failed to create issue: #{responce.code} #{responce.message}\n#{responce.body}"
          end
        end

        private

        def post_issue
          uri = URI("https://api.github.com/repos/#{@repo}/issues")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true

          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = issue_body.to_json

          http.request(request)
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
