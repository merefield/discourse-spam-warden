# frozen_string_literal: true

RSpec.describe Admin::SiteSettingsController do
  fab!(:admin)

  it "exposes the scoring defaults, bounds and descriptions in admin settings" do
    sign_in(admin)
    get "/admin/site_settings.json"
    expect(response.status).to eq(200)
    settings = response.parsed_body.fetch("site_settings").index_by { |setting| setting["setting"] }
    {
      "spam_warden_reading_limited_adjustment" => [-5, -100, 0],
      "spam_warden_reading_meaningful_adjustment" => [-10, -100, 0],
      "spam_warden_reading_sustained_adjustment" => [-15, -100, 0],
      "spam_warden_no_reading_adjustment" => [10, 0, 100],
      "spam_warden_confirmed_spam_points" => [85, 0, 100],
      "spam_warden_email_report_points" => [8, 0, 100],
      "spam_warden_email_points_cap" => [60, 0, 100],
      "spam_warden_ip_report_points" => [3, 0, 100],
      "spam_warden_ip_points_cap" => [30, 0, 100],
      "spam_warden_local_points_cap" => [100, 0, 100],
      "spam_warden_email_moderate_confidence" => [50, 0, 100],
      "spam_warden_email_moderate_frequency" => [3, 1, 10_000],
    }.each do |name, (default, minimum, maximum)|
      setting = settings.fetch(name)
      expect(setting["default"].to_i).to eq(default)
      expect(setting["description"]).to be_present
      expect(setting["min"]).to eq(minimum)
      expect(setting["max"]).to eq(maximum)
    end
  end
end
