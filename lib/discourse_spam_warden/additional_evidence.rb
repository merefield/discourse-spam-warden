# frozen_string_literal: true

module DiscourseSpamWarden
  class AdditionalEvidence
    MAX_POINTS = 25

    def self.collect(user_id:, source:)
      entries =
        DiscoursePluginRegistry.apply_modifier(
          :spam_warden_additional_evidence,
          [],
          user_id,
          source,
        )
      return [] unless entries.is_a?(Array)
      entries
        .first(10)
        .filter_map do |entry|
          next unless entry.is_a?(Hash)
          label = entry["label"]
          points = entry["points"]
          next unless label.is_a?(String) && label.present? && label.length <= 200
          next unless points.is_a?(Integer) && points.between?(0, MAX_POINTS)
          { "label" => label, "points" => points }
        end
    rescue StandardError => error
      Rails.logger.warn("Spam Warden additional evidence unavailable (#{error.class})")
      []
    end
  end
end
