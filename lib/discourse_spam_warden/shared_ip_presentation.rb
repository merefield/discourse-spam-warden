# frozen_string_literal: true

module DiscourseSpamWarden
  class SharedIpPresentation
    PAGE_SIZE = 25

    def self.call(user, guardian:, after_id: 0)
      raise Discourse::InvalidAccess unless guardian.is_admin? && guardian.can_see_ip?
      own = SharedIp.observations(user)
      scope = SharedIp.matches(own.map { |entry| entry[:ip] }.uniq).where.not(id: user.id)
      users =
        scope
          .select(:id, :username, :created_at, :last_seen_at, :ip_address, :registration_ip_address)
          .where("users.id > ?", after_id)
          .order(:id)
          .limit(PAGE_SIZE + 1)
          .to_a
      more = users.size > PAGE_SIZE
      users = users.first(PAGE_SIZE)
      scans = Scan.latest_for_users(users.map(&:id) + [user.id]).index_by(&:user_id)
      histories =
        UserIpAddressHistory
          .where(user_id: users.map(&:id))
          .where("updated_at >= ?", SharedIp.since)
          .group_by(&:user_id)
      threshold = SiteSetting.spam_warden_shared_ip_suspicion_threshold
      own_score = score(scans[user.id])
      saved = scans[user.id]&.policy&.dig("assessment", "shared_ip")
      eligible = SharedIp.accounts.exists?(id: user.id)
      {
        days: SiteSetting.spam_warden_shared_ip_days,
        threshold: threshold,
        enabled: DiscourseSpamWarden.enabled? && SharedIp.enabled?,
        eligible: eligible,
        own_score: own_score,
        own_qualifies: eligible && !own_score.nil? && own_score >= threshold,
        saved_points: saved&.fetch("points", nil),
        saved_at: scans[user.id]&.created_at,
        total: scope.count,
        next_after_id: more ? users.last.id : nil,
        accounts:
          users.map do |peer|
            peer_score = score(scans[peer.id])
            connections =
              SharedIp
                .observations(peer, histories: histories.fetch(peer.id, []))
                .flat_map do |other|
                  own.filter_map do |entry|
                    next unless entry[:ip] == other[:ip]
                    {
                      ip: entry[:ip],
                      source: entry[:source],
                      peer_source: other[:source],
                      at: entry[:at],
                      peer_at: other[:at],
                    }
                  end
                end
            {
              id: peer.id,
              username: peer.username,
              independent_score: peer_score,
              qualifies: !peer_score.nil? && peer_score >= threshold,
              checked_at: scans[peer.id]&.created_at,
              connection_types: connections.map { |entry| entry.slice(:source, :peer_source) }.uniq,
              connections: connections,
            }
          end,
      }
    end

    def self.score(scan)
      if !scan || scan.created_at < SharedIp.since || !scan.policy.dig("assessment", "scored") ||
           !scan.policy.dig("assessment", "calculation")
        return
      end
      SharedIp.independent_score(scan.policy["assessment"])
    end
  end
end
