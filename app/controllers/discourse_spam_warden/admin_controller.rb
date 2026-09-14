# frozen_string_literal: true

module DiscourseSpamWarden
  # Recovery and audit access must remain available after automatic checks are disabled.
  # rubocop:disable Discourse/Plugins/CallRequiresPlugin
  class AdminController < ::Admin::AdminController
    before_action :limit_checks, only: %i[check test_connection submission submit_report]

    def index
      scans = Scan.includes(:user).order(id: :desc).limit(50)
      render json: {
               scans: serialize_data(scans, SpamWardenScanSerializer),
               health: Client.health,
               enabled: DiscourseSpamWarden.enabled?,
               mode: SiteSetting.spam_warden_mode,
               counts: Scan.where("created_at >= ?", 7.days.ago).group(:action_taken).count,
             }
    end

    def check
      CheckAccount.call(**service_params) do
        on_success do |scan:|
          render json: {
                   scan: scan && SpamWardenScanSerializer.new(scan, scope: guardian, root: false),
                 }
        end
        on_failure { render_json_error(I18n.t("spam_warden.check_failed")) }
        on_model_not_found(:user) { raise Discourse::NotFound }
        on_failed_policy(:can_check_account) { raise Discourse::InvalidAccess }
      end
    end

    def test_connection
      result = Client.new.lookup({ "ip" => "127.0.0.1" }, bypass_cache: true)
      render json: { status: result["status"], health: Client.health }
    end

    def account
      user = User.find(params[:user_id])
      scan = Scan.where(user: user).latest.first
      report = Submission.find_by(user: user)
      render json: {
               ai_evidence: AiIntegration.snapshot(user, guardian: guardian),
               submission_configured: SubmissionCandidate.configured?,
               submission:
                 report && SpamWardenSubmissionSerializer.new(report, scope: guardian, root: false),
               allowed: Account.exists?(user: user, allowed: true),
               enabled: DiscourseSpamWarden.enabled?,
               scan: scan && SpamWardenScanSerializer.new(scan, scope: guardian, root: false),
             }
    end

    def update_exception
      UpdateException.call(**service_params) do
        on_success { head :no_content }
        on_failure { render_json_error(I18n.t("spam_warden.check_failed")) }
        on_model_not_found(:user) { raise Discourse::NotFound }
        on_failed_policy(:can_manage_exception) { raise Discourse::InvalidAccess }
      end
    end

    def submission
      raise Discourse::InvalidAccess unless current_user.human?
      user = User.find(params[:user_id])
      report = Submission.find_by(user: user)
      protected = report && Submission::PROTECTED_STATUSES.include?(report.status)
      candidate = SubmissionCandidate.latest(user) if SubmissionCandidate.configured? && !protected
      if candidate
        StaffActionLogger.new(current_user).log_custom(
          "spam_warden_submission_preview",
          user_id: user.id,
        )
      end
      render json: {
               configured: SubmissionCandidate.configured?,
               submission:
                 report && SpamWardenSubmissionSerializer.new(report, scope: guardian, root: false),
               preview:
                 candidate &&
                   SpamWardenSubmissionPreviewSerializer.new(
                     candidate,
                     scope: guardian,
                     root: false,
                   ),
             }
    end

    def submit_report
      SubmitReport.call(**service_params) do
        on_success do |submission:|
          render json: {
                   submission:
                     SpamWardenSubmissionSerializer.new(submission, scope: guardian, root: false),
                 },
                 status: :accepted
        end
        on_failed_policy(:can_submit) { raise Discourse::InvalidAccess }
        on_model_not_found(:user) { raise Discourse::NotFound }
        on_failure { render_json_error(I18n.t("spam_warden.submission_failed")) }
      end
    end

    private

    def limit_checks
      RateLimiter.new(current_user, "spam-warden-check", 10, 1.minute).performed!
    end
  end
  # rubocop:enable Discourse/Plugins/CallRequiresPlugin
end
