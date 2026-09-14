# frozen_string_literal: true

RSpec.describe Admin::UsersController do
  fab!(:admin)
  fab!(:user)
  fab!(:moderator)

  describe "#index" do
    it "returns the most recent retained assessment and exemption even when checks are disabled" do
      DiscourseSpamWarden::Scan.create!(
        user: user,
        source: "manual",
        status: "checked",
        decision: "silence",
        created_at: 1.day.ago,
      )
      latest =
        DiscourseSpamWarden::Scan.create!(
          user: user,
          source: "manual",
          status: "unknown",
          decision: "unknown",
        )
      DiscourseSpamWarden::Account.create!(user: user, allowed: true)
      sign_in(admin)

      get "/admin/users/list.json", params: { filter: user.username }

      expect(response.status).to eq(200)
      summary =
        response.parsed_body.find { |row| row["id"] == user.id }.fetch("spam_warden_summary")
      expect(summary).to include("exempt" => true)
      expect(summary["scan"]).to include(
        "status" => "unknown",
        "decision" => "unknown",
        "scored" => false,
        "score" => nil,
      )
      expect(Time.zone.parse(summary["scan"]["checked_at"]).to_i).to eq(latest.created_at.to_i)
    end

    it "distinguishes accounts without a retained assessment" do
      sign_in(admin)
      get "/admin/users/list.json", params: { filter: user.username }
      expect(response.parsed_body.find { |row| row["id"] == user.id }["spam_warden_summary"]).to eq(
        "exempt" => false,
        "scan" => nil,
      )
    end

    it "breaks equal-time ties consistently and excludes other users' scans" do
      freeze_time
      DiscourseSpamWarden::Scan.create!(
        user: user,
        source: "manual",
        status: "checked",
        decision: "allow",
      )
      latest =
        DiscourseSpamWarden::Scan.create!(
          user: user,
          source: "activity",
          status: "checked",
          decision: "review",
        )
      DiscourseSpamWarden::Scan.create!(
        user: moderator,
        source: "manual",
        status: "checked",
        decision: "silence",
      )
      DiscourseSpamWarden::Scan.create!(
        user: user,
        source: "manual",
        status: "checked",
        decision: "watch",
        created_at: 1.day.ago,
      )

      summaries = DiscourseSpamWarden::Scan.latest_for_users([user.id])

      expect(summaries.map(&:user_id)).to eq([user.id])
      expect(summaries.first.decision).to eq(latest.decision)
      expect(DiscourseSpamWarden::Scan.where(user: user).latest.first).to eq(latest)
    end

    it "exposes the same saved score used by the account dashboard" do
      DiscourseSpamWarden::Scan.create!(
        user: user,
        source: "manual",
        status: "checked",
        decision: "review",
        policy: {
          assessment: {
            score: 65,
            scored: true,
          },
        },
      )
      sign_in(admin)
      get "/admin/users/list.json", params: { filter: user.username }
      summary =
        response.parsed_body.find { |row| row["id"] == user.id }.fetch("spam_warden_summary")
      expect(summary["scan"]).to include("score" => 65, "scored" => true, "decision" => "review")
    end

    it "keeps the summary restricted to administrators" do
      sign_in(moderator)
      get "/admin/users/list.json", params: { filter: user.username }
      expect(response.status).to eq(200)
      expect(response.parsed_body.find { |row| row["id"] == user.id }).not_to have_key(
        "spam_warden_summary",
      )
    end

    it "batch loads summary data independently of the number of listed users" do
      sign_in(admin)
      get "/admin/users/list.json"
      queries = track_sql_queries { get "/admin/users/list.json" }
      expect(response.parsed_body.count { |row| row.key?("spam_warden_summary") }).to be >= 3
      expect(
        queries.count { |sql| sql.include?("JOIN LATERAL") && sql.include?("spam_warden_scans") },
      ).to eq(1)
      expect(queries.count { |sql| sql.include?("FROM \"spam_warden_accounts\"") }).to eq(1)
    end
  end
end
