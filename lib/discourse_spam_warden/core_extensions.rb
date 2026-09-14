# frozen_string_literal: true

module DiscourseSpamWarden
  module CoreExtensions
    module FlaggedPost
      attr_writer :spam_warden_scan, :spam_warden_ai_review

      def spam_warden_scan
        return @spam_warden_scan if defined?(@spam_warden_scan)
        @spam_warden_scan = DiscourseSpamWarden::Scan.where(reviewable_id: id).latest.first
      end

      def spam_warden_ai_review?
        return @spam_warden_ai_review if defined?(@spam_warden_ai_review)
        @spam_warden_ai_review =
          DiscourseSpamWarden::AiIntegration.ai_review_ids([self]).include?(id)
      end
    end

    module AdminUsersController
      def serialize_data(object, serializer, options = nil)
        if serializer == AdminUserListSerializer
          DiscourseSpamWarden::AdminUserList.preload(object, guardian)
        end
        super
      end
    end

    module ReviewableQuery
      def list_for(*args, **options)
        result = super
        options.fetch(:preload, true) ? result.extending(ReviewableRelation) : result
      end
    end

    module ReviewableRelation
      def records
        super.tap { |reviews| DiscourseSpamWarden::ReviewEvidence.preload(reviews) }
      end
    end
  end
end
