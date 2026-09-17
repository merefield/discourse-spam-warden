# frozen_string_literal: true

module DiscourseSpamWarden
  class ReviewEvidence
    def self.preload(reviewables)
      flagged =
        reviewables
          .grep(ReviewableFlaggedPost)
          .reject do |review|
            review.instance_variable_defined?(:@spam_warden_scan) &&
              review.instance_variable_defined?(:@spam_warden_ai_review)
          end
      if flagged.present?
        scans =
          Scan
            .where(reviewable_id: flagged.map(&:id))
            .select("DISTINCT ON (reviewable_id) spam_warden_scans.*")
            .reorder(:reviewable_id, created_at: :desc, id: :desc)
            .includes(:user)
            .index_by(&:reviewable_id)
        ai_ids = AiIntegration.ai_review_ids(flagged)
        flagged.each do |review|
          review.spam_warden_scan = scans[review.id]
          review.spam_warden_ai_review = ai_ids.include?(review.id)
        end
      end
      reviews =
        reviewables
          .grep(ReviewableSpamWarden)
          .reject { |review| review.instance_variable_defined?(:@spam_warden_scan) }
      return if reviews.empty?

      scans = Scan.where(id: reviews.map { |review| review.payload["scan_id"] }).index_by(&:id)
      reviews.each do |review|
        scan = scans[review.payload["scan_id"]]
        scan.association(:user).target = review.target if scan
        review.spam_warden_scan = scan
      end
    end
  end
end
