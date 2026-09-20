# frozen_string_literal: true

# name: discourse-spam-warden
# about: Explainable Stop Forum Spam reputation checks and moderation tools.
# version: 0.2.1
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-spam-warden

# Admin reporting and recovery remain available independently of lookup activation.
register_asset "stylesheets/common/spam-warden.scss"
%w[
  circle-check
  circle-exclamation
  circle-question
  triangle-exclamation
  user-check
  user-slash
].each { |icon| register_svg_icon icon }
add_admin_route "spam_warden.title", "discourse-spam-warden", use_new_show_route: true

module ::DiscourseSpamWarden
  PLUGIN_NAME = "discourse-spam-warden"
  EXTENSION_API_VERSION = 1

  def self.enabled?
    SiteSetting.spam_warden_enabled
  end
end

# Compatibility for the separately installed, pre-rename Pro extension.
DiscourseSpamGuard = DiscourseSpamWarden # rubocop:disable Discourse/Plugins/NamespaceConstants

require_relative "lib/discourse_spam_warden/engine"

after_initialize do
  register_reviewable_type ReviewableSpamWarden

  reloadable_patch do
    ReviewableFlaggedPost.prepend(DiscourseSpamWarden::CoreExtensions::FlaggedPost)
    Admin::UsersController.prepend(DiscourseSpamWarden::CoreExtensions::AdminUsersController)
    Reviewable.singleton_class.prepend(DiscourseSpamWarden::CoreExtensions::ReviewableQuery)
  end

  add_to_serializer(
    :admin_user_list,
    :spam_warden_summary,
    respect_plugin_enabled: false,
    include_condition: -> do
      scope.is_admin? && object.instance_variable_defined?(:@spam_warden_summary)
    end,
  ) { object.instance_variable_get(:@spam_warden_summary) }

  on(:reviewable_score_updated) do |review|
    DiscourseSpamWarden::AiIntegration.enqueue_reconciliation(review)
  end

  add_to_serializer(
    :reviewable_flagged_post,
    :spam_warden_scan,
    respect_plugin_enabled: false,
    include_condition: -> { scope.is_staff? && object.spam_warden_scan.present? },
  ) { SpamWardenScanSerializer.new(object.spam_warden_scan, scope: scope, root: false).as_json }

  add_to_serializer(
    :reviewable_flagged_post,
    :spam_warden_ai_account_id,
    respect_plugin_enabled: false,
    include_condition: -> { scope.is_admin? && object.spam_warden_ai_review? },
  ) { object.target_created_by_id }

  on(:user_created) do |user|
    if DiscourseSpamWarden.enabled? && user.human? && !user.staff?
      Jobs.enqueue(:spam_warden_check, user_id: user.id, source: "registration")
      hours = SiteSetting.spam_warden_recheck_hours
      if hours > 0
        Jobs.enqueue_in(hours.hours, :spam_warden_check, user_id: user.id, source: "recheck")
      end
    end
  end

  on(:post_created) do |post, *_args|
    if post.post_type == Post.types[:regular] && post.topic&.archetype == Archetype.default &&
         !post.topic.category&.read_restricted?
      DiscourseSpamWarden::LocalSignals.enqueue(post.user)
    end
  end

  on(:reviewable_transitioned_to) do |_status, reviewable|
    if reviewable.is_a?(ReviewableFlaggedPost)
      DiscourseSpamWarden::LocalSignals.enqueue(reviewable.target_created_by)
    end
  end

  # Privacy cleanup must also run while automatic checking is disabled.
  # rubocop:disable Discourse/Plugins/UsePluginInstanceOn
  DiscourseEvent.on(:user_destroyed) do |user|
    DiscourseSpamWarden::Submission.where(user_id: user.id).delete_all
    DiscourseSpamWarden::Scan.where(user_id: user.id).delete_all
    DiscourseSpamWarden::Account.where(user_id: user.id).delete_all
  end

  DiscourseEvent.on(:user_anonymized) do |user:, **_opts|
    DiscourseSpamWarden::Submission.where(user_id: user.id).delete_all
    DiscourseSpamWarden::Scan.where(user_id: user.id).delete_all
    DiscourseSpamWarden::Account.where(user_id: user.id).delete_all
  end
  # rubocop:enable Discourse/Plugins/UsePluginInstanceOn
end
