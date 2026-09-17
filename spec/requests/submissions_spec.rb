# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::AdminController do
  fab!(:user)
  fab!(:admin)
  fab!(:moderator)
  fab!(:spam_post) { Fabricate(:spam_warden_confirmed_post, user: user) }
  let(:url) { "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/submission.json" }

  before do
    SiteSetting.spam_warden_submissions_enabled = true
    SiteSetting.spam_warden_submission_api_key = "private-test-key"
    Jobs.run_later!
  end

  describe "GET /admin/plugins/discourse-spam-warden/accounts/:user_id/submission" do
    it "denies anonymous, ordinary and moderator access to identifiers" do
      get url
      expect(response.status).to eq(404)
      [user, moderator].each do |actor|
        sign_in(actor)
        get url
        expect(response.status).to eq(404)
        expect(response.body).not_to include(user.email)
      end
    end

    it "previews exactly the outgoing identifiers and evidence without exposing credentials" do
      sign_in(admin)
      get url
      expect(response.status).to eq(200)
      expect(response.parsed_body["preview"]).to include(
        "email" => user.email,
        "destination" => DiscourseSpamWarden::SubmissionClient::ENDPOINT,
        "ip_address" => user.registration_ip_address.to_s,
        "post_id" => spam_post.id,
      )
      expect(response.body).not_to include(SiteSetting.spam_warden_submission_api_key)
    end
  end

  describe "POST /admin/plugins/discourse-spam-warden/accounts/:user_id/submission" do
    it "denies non-admin submission" do
      [user, moderator].each do |actor|
        sign_in(actor)
        post url, params: { token: "invalid", confirmed: true }
        expect(response.status).to eq(404)
      end
      expect(DiscourseSpamWarden::Submission.count).to eq(0)
    end

    it "queues explicitly approved evidence and keeps credentials out of its response" do
      sign_in(admin)
      get url
      token = response.parsed_body.dig("preview", "token")
      post url, params: { token: token, confirmed: true }
      expect(response.status).to eq(202)
      expect(response.parsed_body.dig("submission", "status")).to eq("pending")
      expect(response.parsed_body.dig("submission", "events").last).to include(
        "actor_id" => admin.id,
        "actor_username" => admin.username,
      )
      expect(response.body).not_to include(SiteSetting.spam_warden_submission_api_key)
    end
  end
end
