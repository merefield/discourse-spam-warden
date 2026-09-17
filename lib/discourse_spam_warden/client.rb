# frozen_string_literal: true

require "net/http"
require "ipaddr"
require "digest"

module DiscourseSpamWarden
  class Client
    ENDPOINTS = {
      "closest" => "https://api.stopforumspam.org/api",
      "europe" => "https://europe.stopforumspam.org/api",
    }.freeze
    CACHE_SECONDS = 1.hour.to_i
    MAX_RESPONSE_BYTES = 64 * 1024
    TIMEOUT_SECONDS = 4
    HEALTH_KEY = "spam_warden:health"
    CIRCUIT_KEY = "spam_warden:circuit"

    class InvalidResponse < StandardError
    end

    def self.health
      JSON.parse(Discourse.redis.get(HEALTH_KEY) || "{}")
    end

    def self.identifiers(user)
      fields = {}
      fields["email"] = user.email if SiteSetting.spam_warden_check_email && user.email.present?
      if SiteSetting.spam_warden_check_ip && user.registration_ip_address.present?
        ip = IPAddr.new(user.registration_ip_address.to_s)
        fields["ip"] = ip.to_s unless ip.private? || ip.loopback? || ip.link_local? || ip.to_i.zero?
      end
      fields["username"] = user.username if SiteSetting.spam_warden_check_username
      fields
    rescue IPAddr::InvalidAddressError
      fields
    end

    def lookup(fields, bypass_cache: false)
      if fields.empty?
        return { "status" => "skipped", "evidence" => {}, "error_code" => "no_identifiers" }
      end
      endpoint = ENDPOINTS.fetch(SiteSetting.spam_warden_region)
      digest = Digest::SHA256.hexdigest([endpoint, fields.sort].to_json)
      key = "spam_warden:lookup:#{digest}"
      if !bypass_cache && (cached = Discourse.redis.get(key))
        return JSON.parse(cached)
      end
      if Discourse.redis.exists?(CIRCUIT_KEY)
        return unavailable("circuit_open", update_health: false)
      end
      lease = SecureRandom.hex(12)
      unless Discourse.redis.set("spam_warden:provider", lease, nx: true, ex: 30)
        return unavailable("busy", update_health: false)
      end
      begin
        result = normalize(request(endpoint, fields), fields.keys)
      ensure
        Discourse.redis.eval(
          "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) end",
          keys: [Discourse.redis.namespace_key("spam_warden:provider")],
          argv: [lease],
        )
      end
      Discourse.redis.setex(key, CACHE_SECONDS, result.to_json)
      health =
        self.class.health.merge("status" => "healthy", "last_success_at" => Time.now.utc.iso8601)
      Discourse.redis.setex(HEALTH_KEY, 30.days.to_i, health.to_json)
      result
    rescue JSON::ParserError, InvalidResponse, ArgumentError, TypeError, KeyError
      unavailable("invalid_response")
    rescue Net::OpenTimeout,
           Net::ReadTimeout,
           Timeout::Error,
           SocketError,
           IOError,
           SystemCallError,
           OpenSSL::SSL::SSLError
      unavailable("unavailable")
    end

    private

    def request(endpoint, fields)
      uri = URI(endpoint)
      request = Net::HTTP::Post.new(uri)
      request["User-Agent"] = "Discourse-Spam-Warden/0.1"
      request.set_form_data(fields.merge("f" => "json", "confidence" => "1", "nobadall" => "1"))
      body = +""
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
            raise InvalidResponse unless response.code == "200"
            response.read_body do |chunk|
              body << chunk
              raise InvalidResponse if body.bytesize > MAX_RESPONSE_BYTES
            end
          end
        end
      end
      JSON.parse(body)
    end

    def normalize(body, fields)
      raise InvalidResponse unless body.is_a?(Hash) && [1, true].include?(body["success"])
      evidence =
        fields.to_h do |field|
          data = body[field]
          unless data.is_a?(Hash) && [0, 1, false, true].include?(data["appears"])
            raise InvalidResponse
          end
          appears = [1, true].include?(data["appears"])
          frequency = Integer(data.fetch("frequency"))
          confidence = data["confidence"].nil? ? nil : Float(data["confidence"])
          if frequency < 0 || (confidence && (!confidence.finite? || !confidence.between?(0, 100)))
            raise InvalidResponse
          end
          last_seen = Time.zone.parse(data["lastseen"].to_s)&.utc&.iso8601 if data[
            "lastseen"
          ].present?
          [
            field,
            {
              "appears" => appears,
              "frequency" => frequency,
              "confidence" => confidence,
              "last_seen" => last_seen,
              "blacklisted" => [1, true].include?(data["blacklisted"]),
            },
          ]
        end
      { "status" => "checked", "evidence" => evidence }
    end

    def unavailable(code, update_health: true)
      if update_health
        Discourse.redis.setex(CIRCUIT_KEY, 60, "1")
        health =
          self.class.health.merge("status" => "degraded", "last_error_at" => Time.now.utc.iso8601)
        Discourse.redis.setex(HEALTH_KEY, 30.days.to_i, health.to_json)
      end
      { "status" => "unknown", "evidence" => {}, "error_code" => code }
    end
  end
end
