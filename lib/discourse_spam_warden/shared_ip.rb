# frozen_string_literal: true

module DiscourseSpamWarden
  class SharedIp
    def self.enabled?
      SiteSetting.spam_warden_local_signals && SiteSetting.spam_warden_shared_ip_points.positive?
    end

    def self.since
      SiteSetting.spam_warden_shared_ip_days.days.ago
    end

    def self.accounts
      User
        .real
        .where(admin: false, moderator: false)
        .where.not(id: Account.where(allowed: true).select(:user_id))
    end

    def self.observations(user, histories: nil)
      records = []
      if user.created_at >= since && user.registration_ip_address
        records << {
          ip: user.registration_ip_address.to_s,
          source: "registration",
          at: user.created_at,
        }
      end
      if user.ip_address && (user.last_seen_at || user.created_at) >= since
        records << {
          ip: user.ip_address.to_s,
          source: "latest_access",
          at: user.last_seen_at || user.created_at,
        }
      end
      histories ||= UserIpAddressHistory.where(user_id: user.id).where("updated_at >= ?", since)
      histories.each do |entry|
        records << { ip: entry.ip_address.to_s, source: "retained_history", at: entry.updated_at }
      end
      records
    end

    def self.addresses(user)
      observations(user).map { |entry| entry[:ip] }.uniq
    end

    def self.matches(addresses)
      return accounts.none if addresses.empty?
      registration =
        User.where(registration_ip_address: addresses).where("created_at >= ?", since).select(:id)
      latest =
        User
          .where(ip_address: addresses)
          .where("COALESCE(last_seen_at, created_at) >= ?", since)
          .select(:id)
      history =
        UserIpAddressHistory
          .where(ip_address: addresses)
          .where("updated_at >= ?", since)
          .select(:user_id)
      accounts.where(
        "users.id IN (#{registration.to_sql} UNION #{latest.to_sql} UNION #{history.to_sql})",
      )
    end

    def self.independent_score(assessment)
      calculation = assessment&.dig("calculation")
      return 0 unless calculation && assessment["scored"]
      email = assessment.dig("external_scoring", "points", "email").to_f
      local = [
        calculation.fetch("posting", 0) + calculation.fetch("additional", 0),
        calculation.fetch("local_cap", 100),
      ].min
      [
        100,
        [0, email + local + calculation.fetch("reading", 0)].max +
          calculation.fetch("confirmed", 0),
      ].min
    end

    def self.snapshot(user, assessment)
      result = { "points" => 0, "related_accounts" => 0, "suspicious_accounts" => 0 }
      return result unless enabled?
      related = Set.new
      suspicious = Set.new
      threshold = SiteSetting.spam_warden_shared_ip_suspicion_threshold
      addresses(user).each do |address|
        members = matches([address])
        next unless members.where.not(id: user.id).exists?
        qualifying = []
        qualifying << user.id if independent_score(assessment) >= threshold
        # Read only the newest scan per account; older suspicion must not survive a clean recheck.
        DB
          .query(<<~SQL, cutoff: since)
          SELECT users.id, latest.policy
          FROM (#{members.where.not(id: user.id).select(:id).to_sql}) AS users
          JOIN LATERAL (
            SELECT policy, created_at FROM spam_warden_scans
            WHERE user_id = users.id
            ORDER BY created_at DESC, id DESC LIMIT 1
          ) latest ON latest.created_at >= :cutoff
        SQL
          .each do |row|
            policy = row.policy.is_a?(String) ? JSON.parse(row.policy) : row.policy
            qualifying << row.id if independent_score(policy["assessment"]) >= threshold
          end
        next if qualifying.empty?
        related.merge(members.where.not(id: user.id).pluck(:id))
        suspicious.merge(qualifying)
      end
      if related.any?
        result = {
          "points" => SiteSetting.spam_warden_shared_ip_points,
          "related_accounts" => related.size,
          "suspicious_accounts" => suspicious.size,
        }
      end
      result.merge("threshold" => threshold, "days" => SiteSetting.spam_warden_shared_ip_days)
    end

    def self.enqueue(user)
      return unless enabled?
      DB.after_commit do
        key = "spam_warden:shared_ip_refresh:#{user.id}"
        if Discourse.redis.set(key, "1", nx: true, ex: 60)
          begin
            Jobs.enqueue_in(1.minute, :spam_warden_shared_ip_refresh, user_id: user.id)
          rescue StandardError
            Discourse.redis.del(key)
            raise
          end
        end
      end
    end
  end
end
