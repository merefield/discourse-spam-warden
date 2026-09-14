# frozen_string_literal: true

module DiscourseSpamWarden
  class Policy
    def self.weights
      {
        "reading_limited" => SiteSetting.spam_warden_reading_limited_adjustment,
        "reading_meaningful" => SiteSetting.spam_warden_reading_meaningful_adjustment,
        "reading_sustained" => SiteSetting.spam_warden_reading_sustained_adjustment,
        "no_reading" => SiteSetting.spam_warden_no_reading_adjustment,
        "confirmed_spam" => SiteSetting.spam_warden_confirmed_spam_points,
        "local_cap" => SiteSetting.spam_warden_local_points_cap,
      }
    end

    FULL_WEIGHT_DAYS = 7
    HALF_WEIGHT_DAYS = 30

    def self.external_weights
      {
        "email_report_points" => SiteSetting.spam_warden_email_report_points,
        "email_points_cap" => SiteSetting.spam_warden_email_points_cap,
        "ip_report_points" => SiteSetting.spam_warden_ip_report_points,
        "ip_points_cap" => SiteSetting.spam_warden_ip_points_cap,
        "full_weight_days" => FULL_WEIGHT_DAYS,
        "half_weight_days" => HALF_WEIGHT_DAYS,
        "email_moderate_confidence" => SiteSetting.spam_warden_email_moderate_confidence,
        "email_moderate_frequency" => SiteSetting.spam_warden_email_moderate_frequency,
      }
    end

    def self.settings
      {
        "version" => 8,
        "weights" => weights,
        "external_weights" => external_weights,
        "preset" => SiteSetting.spam_warden_preset,
        "mode" => SiteSetting.spam_warden_mode,
        "email_confidence" => SiteSetting.spam_warden_email_confidence,
        "email_frequency" => SiteSetting.spam_warden_email_frequency,
        "ip_confidence" => SiteSetting.spam_warden_ip_confidence,
        "ip_frequency" => SiteSetting.spam_warden_ip_frequency,
        "max_age_days" => SiteSetting.spam_warden_max_evidence_age_days,
      }
    end

    def self.assess(
      evidence,
      settings,
      engagement:,
      status:,
      local_signals: nil,
      additional_evidence: []
    )
      external = status == "checked" ? evaluate(evidence, settings) : "unknown"
      external_scoring = score_external(evidence, settings) if status == "checked"
      base = external_scoring&.fetch("score")
      reading = engagement.fetch("adjustment")
      confirmed_points = local_signals&.fetch("history_points", 0) || 0
      posting_points =
        local_signals&.fetch("posting_points") do
          local_signals.fetch("adjustment", 0) - confirmed_points
        end || 0
      local_cap = settings.fetch("weights") { weights }.fetch("local_cap")
      additional_points = [
        additional_evidence.sum { |entry| entry.fetch("points") },
        AdditionalEvidence::MAX_POINTS,
        [local_cap - posting_points, 0].max,
      ].min
      local_points = posting_points + additional_points
      capped_local = [local_points, local_cap].min
      if base
        suspicion = [0, base + capped_local + reading].max
        score = [100, suspicion + confirmed_points].min
        calculation = {
          "external" => base,
          "posting" => posting_points,
          "posting_cap" => LocalSignals::POSTING_CAP,
          "additional" => additional_points,
          "local_cap" => local_cap,
          "capped_local" => capped_local,
          "reading" => reading,
          "suspicion" => suspicion,
          "confirmed" => confirmed_points,
          "total_before_cap" => suspicion + confirmed_points,
          "total" => score,
        }
      end
      decision = external
      decision = "watch" if external == "allow" && score && score >= 10
      # Display scoring must not relax automatic-silencing safeguards.
      decision = "review" if external == "silence" && reading < -5
      if %w[allow watch unknown].include?(decision)
        decision = "watch" if local_points.positive? && !base.nil?
        decision = "review" if local_points >= LocalSignals::POSTING_CAP
      end
      if %w[allow watch unknown].include?(decision) &&
           local_signals&.fetch("confirmed_spam_posts", 0).to_i.positive?
        decision = "review"
      end
      {
        "external_decision" => external,
        "external_scoring" => external_scoring,
        "scored" => !base.nil?,
        "base_score" => base,
        "score" => score,
        "calculation" => calculation,
        "decision" => decision,
        "engagement" => engagement,
        "local_signals" => local_signals,
        "additional_evidence" => additional_evidence,
        "additional_points" => additional_points,
      }
    end

    def self.qualifies?(data, field, settings, moderate: false)
      return false unless data && data["appears"] && !data["blacklisted"]
      return false unless data["last_seen"] && !data["confidence"].nil?

      seen = Time.zone.parse(data["last_seen"])
      return false unless seen && seen <= Time.current && seen >= settings["max_age_days"].days.ago

      thresholds = moderate ? settings.fetch("external_weights") { external_weights } : settings
      prefix = moderate ? "#{field}_moderate" : field
      data["frequency"] >= thresholds.fetch("#{prefix}_frequency") &&
        data["confidence"].to_f >= thresholds.fetch("#{prefix}_confidence")
    rescue ArgumentError, TypeError
      false
    end

    def self.score_external(evidence, settings)
      weights = settings.fetch("external_weights") { external_weights }
      fields =
        %w[email ip].index_with do |field|
          data = evidence[field] || {}
          reports = [data.fetch("frequency", 0).to_i, 0].max
          weight = weights.fetch("#{field}_report_points")
          cap = weights.fetch("#{field}_points_cap")
          reason = evidence.key?(field) ? recency_reason(data, weights) : "not_checked"
          multiplier = { "full" => 1, "half" => 0.5 }.fetch(reason, 0)
          capped = [reports * weight, cap].min
          {
            "reports" => reports,
            "weight" => weight,
            "cap" => cap,
            "before_recency" => capped,
            "multiplier" => multiplier,
            "reason" => reason,
            "points" => (capped * multiplier).round(1),
          }
        end
      points = fields.transform_values { |field| field.fetch("points") }
      { "score" => points.values.sum, "points" => points, "fields" => fields }
    end

    def self.recency_reason(data, weights)
      return "blacklisted" if data["blacklisted"]
      return "no_match" unless data["appears"]
      return "undated" if data["last_seen"].blank?
      seen = Time.zone.parse(data["last_seen"])
      return "undated" unless seen
      return "future" if seen > Time.current
      return "full" if seen >= weights.fetch("full_weight_days").days.ago
      return "half" if seen >= weights.fetch("half_weight_days").days.ago
      "expired"
    rescue ArgumentError, TypeError
      "undated"
    end

    def self.evaluate(evidence, settings = self.settings)
      strong = %w[email ip].select { |field| qualifies?(evidence[field], field, settings) }
      if strong.include?("email") && (settings["preset"] == "balanced" || strong.include?("ip"))
        "silence"
      elsif strong.any? || qualifies?(evidence["email"], "email", settings, moderate: true)
        "review"
      elsif evidence.values.any? { |data| data["appears"] || data["blacklisted"] }
        "watch"
      else
        "allow"
      end
    end
  end
end
