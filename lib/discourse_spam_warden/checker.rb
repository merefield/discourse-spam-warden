# frozen_string_literal: true

module DiscourseSpamWarden
  class Checker
    def self.call(user, source:)
      DistributedMutex.synchronize("spam_warden:user:#{user.id}") do
        return if !DiscourseSpamWarden.enabled? || !user.human? || user.staff?
        return if Account.exists?(user: user, allowed: true)
        return if source == "activity" && !SiteSetting.spam_warden_local_signals
        if source != "manual"
          previous = Scan.where(user: user, source: source).latest.first
          if source == "activity"
            return previous if previous && previous.created_at > 1.minute.ago
          else
            return previous if previous && previous.status != "unknown"
          end
          return if user.created_at < 7.days.ago || user.trust_level > 1
        end

        fields = Client.identifiers(user)
        result = Client.new.lookup(fields, bypass_cache: source == "manual")
        weights = Policy.weights
        engagement = Engagement.snapshot(user, source: source, weights: weights)
        local_signals = LocalSignals.snapshot(user, weights: weights)
        additional_evidence = AdditionalEvidence.collect(user_id: user.id, source: source)
        scan = nil
        user.with_lock do
          if !DiscourseSpamWarden.enabled? || !user.human? || user.staff? ||
               Account.exists?(user: user, allowed: true)
            return
          end
          return if source != "manual" && (user.created_at < 7.days.ago || user.trust_level > 1)
          return if source == "activity" && !SiteSetting.spam_warden_local_signals
          return if fields != Client.identifiers(user)
          local_signals = {
            "enabled" => false,
            "adjustment" => 0,
          } unless SiteSetting.spam_warden_local_signals
          settings = Policy.settings
          settings["weights"] = weights
          settings["assessment"] = Policy.assess(
            result["evidence"],
            settings,
            engagement: engagement,
            status: result["status"],
            local_signals: local_signals,
            additional_evidence: additional_evidence,
          )
          decision = settings["assessment"]["decision"]
          scan =
            Scan.create!(
              user: user,
              source: source,
              status: result["status"],
              decision: decision,
              evidence: result["evidence"],
              policy: settings,
              error_code: result["error_code"],
            )
          if SiteSetting.spam_warden_mode != "observe" && %w[review silence].include?(decision)
            reviewable = AiIntegration.pending_review(user)
            unless reviewable
              reviewable =
                ReviewableSpamWarden.needs_review!(
                  target: user,
                  target_created_by: user,
                  created_by: Discourse.system_user,
                  reviewable_by_moderator: true,
                  payload: {
                  },
                )
              reviewable.update!(payload: { "scan_id" => scan.id })
              unless reviewable.reviewable_scores.pending.exists?
                reviewable.add_score(
                  Discourse.system_user,
                  ReviewableScore.types[:needs_approval],
                  reason: "spam_warden",
                  force_review: true,
                )
              end
            end
            scan.update!(reviewable: reviewable, action_taken: "review")
            if SiteSetting.spam_warden_mode == "protect" && decision == "silence" &&
                 source != "manual" && !user.silenced? && !user.suspended?
              if Moderation.silence(user, Discourse.system_user, reviewable: reviewable)
                scan.update!(action_taken: "silenced")
              end
            end
          end
        end
        DiscourseEvent.trigger(:spam_warden_checked, scan)
        scan
      end
    end
  end
end
