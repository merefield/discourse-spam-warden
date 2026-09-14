# frozen_string_literal: true

require "net/http"

module DiscourseSpamGuard
  class SubmissionClient
    ENDPOINT = "https://www.stopforumspam.com/add"
    TIMEOUT_SECONDS = 4
    MAX_RESPONSE_BYTES = 16 * 1024

    def submit(payload)
      uri = URI(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request["User-Agent"] = "Discourse-Spam-Guard"
      request.set_form_data(
        payload.merge("api_key" => SiteSetting.spam_guard_submission_api_key, "f" => "json"),
      )
      body = +""
      code = nil
      Timeout.timeout(TIMEOUT_SECONDS * 3) do
        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: TIMEOUT_SECONDS,
          read_timeout: TIMEOUT_SECONDS,
          write_timeout: TIMEOUT_SECONDS,
        ) do |http|
          http.max_retries = 0
          http.request(request) do |response|
            code = response.code
            response.read_body do |chunk|
              body << chunk
              return "unknown", "invalid_response" if body.bytesize > MAX_RESPONSE_BYTES
            end
          end
        end
      end
      return "unknown", "http_error" unless code == "200"
      # The documented legacy success response has HTTP 200 and no body.
      return "submitted", nil if body.strip.empty?
      data = JSON.parse(body)
      return "submitted", nil if data.is_a?(Hash) && [1, true].include?(data["success"])
      if data.is_a?(Hash) && [0, false].include?(data["success"])
        return "rejected", "provider_rejected"
      end
      %w[unknown invalid_response]
    rescue Net::OpenTimeout, SocketError, Errno::ECONNREFUSED
      %w[pending connection_failed]
    rescue JSON::ParserError
      %w[unknown invalid_response]
    rescue Timeout::Error, IOError, SystemCallError, OpenSSL::SSL::SSLError
      %w[unknown delivery_uncertain]
    end
  end
end
