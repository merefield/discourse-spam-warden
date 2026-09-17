# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::AdminController do
  fab!(:admin)
  fab!(:user)

  describe "#index" do
    it "keeps evidence private from ordinary accounts" do
      sign_in(user)
      get "/admin/plugins/discourse-spam-warden/activity.json"
      expect(response.status).to eq(404)
    end

    it "allows administrators to inspect history while automatic checks are disabled" do
      sign_in(admin)
      get "/admin/plugins/discourse-spam-warden/activity.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body).to include("enabled" => false, "scans" => [])
    end
  end

  describe "#check" do
    before { sign_in(admin) }

    it "returns normalized evidence without disclosing identifiers" do
      SiteSetting.spam_warden_enabled = true
      SiteSetting.spam_warden_check_ip = false
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )

      post "/admin/plugins/discourse-spam-warden/check.json", params: { user_id: user.id }

      expect(response.status).to eq(200)
      expect(response.parsed_body["scan"]).to include("decision" => "allow", "source" => "manual")
      expect(response.body).not_to include(user.email)
    end

    it "rejects browser requests impersonating an automatic check" do
      SiteSetting.spam_warden_enabled = true
      post "/admin/plugins/discourse-spam-warden/check.json",
           params: {
             user_id: user.id,
             source: "registration",
           }
      expect(response.status).to eq(403)
      expect(DiscourseSpamWarden::Scan.where(user: user)).to be_empty
    end
  end

  describe "#update_exception" do
    it "supports recovery while checks are disabled and returns no content" do
      sign_in(admin)
      put "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/exception.json",
          params: {
            allowed: true,
          }
      expect(response.status).to eq(204)
      expect(DiscourseSpamWarden::Account.find_by(user: user)).to be_allowed
    end

    it "rejects ordinary accounts without creating an exception" do
      sign_in(user)
      put "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/exception.json",
          params: {
            allowed: true,
          }
      expect(response.status).to eq(404)
      expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty
    end
  end
end
