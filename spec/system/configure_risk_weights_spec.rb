# frozen_string_literal: true

RSpec.describe "Configure Spam Warden risk weights" do
  fab!(:admin)
  let(:settings_page) { PageObjects::Pages::AdminSiteSettings.new }

  before { sign_in(admin) }

  it "lets an admin find and save the per-post weight and reading adjustments" do
    settings_page.visit_filtered_plugin_setting("spam_warden")
    %w[
      email_report_points
      email_points_cap
      ip_report_points
      ip_points_cap
      ai_integration
      reading_limited_adjustment
      reading_meaningful_adjustment
      reading_sustained_adjustment
      no_reading_adjustment
      confirmed_spam_points
      local_points_cap
      email_moderate_frequency
      email_moderate_confidence
    ].each { |suffix| expect(settings_page).to have_setting("spam_warden_#{suffix}") }
    expect(settings_page.find_setting("spam_warden_confirmed_spam_points")).to have_text(
      "Risk points per distinct post",
    )
    expect(settings_page.find_setting("spam_warden_reading_sustained_adjustment")).to have_text(
      "Negative values reduce concern",
    )
    settings_page.fill_setting("spam_warden_confirmed_spam_points", "75")
    settings_page.save_setting("spam_warden_confirmed_spam_points")
    expect(settings_page).to have_overridden_setting(
      "spam_warden_confirmed_spam_points",
      value: "75",
    )
    expect(settings_page.find_setting("spam_warden_email_report_points")).to have_text(
      "does not change moderation thresholds",
    )
    settings_page.fill_setting("spam_warden_email_report_points", "9")
    settings_page.save_setting("spam_warden_email_report_points")
    expect(settings_page).to have_overridden_setting("spam_warden_email_report_points", value: "9")
    page.refresh
    expect(settings_page).to have_overridden_setting(
      "spam_warden_confirmed_spam_points",
      value: "75",
    )
  end
end
