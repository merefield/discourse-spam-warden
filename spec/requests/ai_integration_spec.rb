# frozen_string_literal: true

if defined?(::AiSpamLog)
  RSpec.describe DiscourseSpamWarden::AdminController do
    fab!(:admin)
    fab!(:moderator)
    fab!(:user)
    fab!(:llm_model)
    fab!(:post) { Fabricate(:post, user: user) }
    fab!(:review) { Fabricate(:reviewable_flagged_post, target: post, target_created_by: user) }
    fab!(:spam_score) do
      Fabricate(
        :reviewable_score,
        reviewable: review,
        reviewable_score_type: ReviewableScore.types[:spam],
      )
    end
    fab!(:log) do
      AiSpamLog.create!(
        post: post,
        reviewable: review,
        llm_model: llm_model,
        is_spam: true,
        reason: "AI explanation",
        payload: "Secret model prompt",
      )
    end

    describe "#account" do
      it "returns saved AI evidence only to admins without raw prompts" do
        sign_in(admin)
        get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}.json"
        expect(response.status).to eq(200)
        expect(response.parsed_body.dig("ai_evidence", "entries").sole).to include(
          "reason" => log.reason,
          "outcome" => "pending",
        )
        expect(response.body).not_to include(log.payload)

        sign_in(moderator)
        get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}.json"
        expect(response.status).to eq(404)
        sign_in(user)
        get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}.json"
        expect(response.status).to eq(404)
      end
    end

    describe "review evidence" do
      it "batches linked scan evidence and restricts admin account navigation" do
        scan =
          DiscourseSpamWarden::Scan.create!(
            user: user,
            reviewable: review,
            source: "manual",
            status: "checked",
            decision: "review",
          )
        sign_in(admin)
        queries =
          track_sql_queries { get "/review.json", params: { type: "ReviewableFlaggedPost" } }
        expect(response.status).to eq(200)
        entry = response.parsed_body["reviewables"].find { |item| item["id"] == review.id }
        expect(entry["spam_warden_ai_account_id"]).to eq(user.id)
        expect(entry.dig("spam_warden_scan", "id")).to eq(scan.id)
        expect(queries.count { |sql| sql.include?("FROM \"spam_warden_scans\"") }).to eq(1)
        expect(queries.count { |sql| sql.include?("FROM \"ai_spam_logs\"") }).to eq(1)

        sign_in(moderator)
        get "/review/#{review.id}.json"
        expect(response.status).to eq(200)
        expect(response.parsed_body["reviewable"]).not_to have_key("spam_warden_ai_account_id")
        expect(response.parsed_body.dig("reviewable", "spam_warden_scan", "id")).to eq(scan.id)
        expect(response.body).not_to include(log.payload, log.reason)
      end
    end
  end
end
