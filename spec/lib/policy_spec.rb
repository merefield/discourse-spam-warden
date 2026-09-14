# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Policy do
  describe ".assess" do
    it "retains review for confirmed spam even when its configured contribution is zero" do
      SiteSetting.spam_warden_local_points_cap = 0
      %w[checked unknown].each do |status|
        assessment =
          described_class.assess(
            {},
            described_class.settings,
            engagement: {
              "adjustment" => -15,
            },
            status: status,
            local_signals: {
              "confirmed_spam_posts" => 1,
              "adjustment" => 0,
            },
          )
        expect(assessment["decision"]).to eq("review")
      end
    end

    it "caps posting and extension evidence separately from confirmed spam" do
      SiteSetting.spam_warden_local_points_cap = 25
      assessment =
        described_class.assess(
          {},
          described_class.settings,
          engagement: {
            "adjustment" => -15,
          },
          status: "checked",
          local_signals: {
            "confirmed_spam_posts" => 1,
            "posting_points" => 20,
            "history_points" => 85,
          },
          additional_evidence: [{ "label" => "Additional evidence", "points" => 25 }],
        )
      expect(assessment).to include("score" => 95, "additional_points" => 5, "decision" => "review")
    end
    it "requests local review during an outage without inventing an external score" do
      assessment =
        described_class.assess(
          {},
          described_class.settings,
          engagement: {
            "adjustment" => -30,
          },
          status: "unknown",
          local_signals: {
            "enabled" => true,
            "adjustment" => 50,
          },
        )
      expect(assessment).to include(
        "external_decision" => "unknown",
        "decision" => "review",
        "score" => nil,
        "scored" => false,
      )
    end

    it "caps additional evidence and never promotes it to automatic silence" do
      assessment =
        described_class.assess(
          {},
          described_class.settings,
          engagement: {
            "adjustment" => 0,
          },
          status: "checked",
          additional_evidence: [{ "label" => "Example", "points" => 25 }] * 10,
        )
      expect(assessment).to include(
        "additional_points" => 25,
        "score" => 25,
        "decision" => "review",
      )
    end
    let(:evidence) do
      data = {
        "appears" => true,
        "frequency" => 20,
        "confidence" => 99,
        "last_seen" => 1.day.ago.iso8601,
      }
      { "email" => data, "ip" => data }
    end

    it "keeps strong evidence actionable even with maximum reassurance" do
      assessment =
        described_class.assess(
          evidence,
          described_class.settings,
          engagement: {
            "adjustment" => -30,
          },
          status: "checked",
        )
      expect(assessment).to include(
        "external_decision" => "silence",
        "decision" => "review",
        "score" => 60,
      )
    end

    it "keeps the silence recommendation after only a minimal amount of reading" do
      assessment =
        described_class.assess(
          evidence,
          described_class.settings,
          engagement: {
            "adjustment" => -5,
          },
          status: "checked",
        )
      expect(assessment).to include("decision" => "silence", "score" => 85)
    end

    it "never interprets engagement as a result when the provider is unavailable or skipped" do
      %w[unknown skipped].each do |status|
        [-30, 10].each do |adjustment|
          assessment =
            described_class.assess(
              {},
              described_class.settings,
              engagement: {
                "adjustment" => adjustment,
              },
              status: status,
            )
          expect(assessment).to include("decision" => "unknown", "score" => nil, "scored" => false)
        end
      end
    end

    it "retains weak external evidence even when reassurance reduces the score to zero" do
      assessment =
        described_class.assess(
          { "username" => evidence["email"] },
          described_class.settings,
          engagement: {
            "adjustment" => -30,
          },
          status: "checked",
        )
      expect(assessment).to include("decision" => "watch", "score" => 0)
    end
  end

  describe "report-count scoring" do
    let(:match) do
      { "appears" => true, "frequency" => 3, "confidence" => 40, "last_seen" => 2.days.ago.iso8601 }
    end

    define_method(:assess) do |evidence, reading: 0, settings: described_class.settings, local: nil|
      described_class.assess(
        evidence,
        settings,
        engagement: {
          "adjustment" => reading,
        },
        status: "checked",
        local_signals: local,
      )
    end

    it "calibrates the supplied accounts using cumulative counts and each identifier's recency" do
      [
        [3, 5, 2, 5, 49],
        [9, 2, 1, 20, 73],
        [7, 32, 1, 1, 96],
      ].each do |emails, ips, email_age, ip_age, expected|
        result =
          assess(
            {
              "email" =>
                match.merge("frequency" => emails, "last_seen" => email_age.days.ago.iso8601),
              "ip" => match.merge("frequency" => ips, "last_seen" => ip_age.days.ago.iso8601),
            },
            reading: 10,
          )
        expect(result["score"]).to eq(expected)
        expect(result["calculation"]["total"]).to eq(expected)
      end
    end

    it "applies identifier caps before recency and handles exact boundaries" do
      freeze_time Time.current.change(usec: 0)
      [
        [7.days, 60],
        [7.days + 1.second, 30],
        [30.days, 30],
        [30.days + 1.second, 0],
      ].each do |age, expected|
        result =
          assess({ "email" => match.merge("frequency" => 1000, "last_seen" => age.ago.iso8601) })
        expect(result["base_score"]).to eq(expected)
      end
      result = assess({ "ip" => match.merge("frequency" => 1, "last_seen" => 8.days.ago.iso8601) })
      expect(result["base_score"]).to eq(1.5)
    end

    it "keeps usernames, blacklists, undated, invalid and future-dated matches informational" do
      [nil, "not a date", 1.day.from_now.iso8601].each do |date|
        expect(assess({ "email" => match.merge("last_seen" => date) })).to include(
          "base_score" => 0,
          "decision" => "watch",
        )
      end
      expect(assess({ "email" => match.merge("blacklisted" => true) })["base_score"]).to eq(0)
      expect(assess({ "email" => match.merge("appears" => false) })["base_score"]).to eq(0)
      username_only = assess({ "username" => match })
      expect(username_only["base_score"]).to eq(0)
      expect(username_only.dig("external_scoring", "fields", "email", "reason")).to eq(
        "not_checked",
      )
    end

    it "snapshots custom report weights and caps independently of current settings" do
      saved = described_class.settings
      before = assess({ "email" => match }, settings: saved)
      SiteSetting.spam_warden_email_report_points = 9
      SiteSetting.spam_warden_email_points_cap = 25
      expect(assess({ "email" => match })["base_score"]).to eq(25)
      expect(assess({ "email" => match }, settings: saved)).to eq(before)
      expect(before.dig("external_scoring", "fields", "email")).to include(
        "reports" => 3,
        "weight" => 8,
        "cap" => 60,
        "multiplier" => 1,
        "points" => 24,
      )
    end

    it "keeps review and protection thresholds independent of display weights" do
      SiteSetting.spam_warden_email_report_points = 100
      SiteSetting.spam_warden_email_points_cap = 100
      expect(assess({ "email" => match })).to include("score" => 100, "decision" => "watch")
      strong = match.merge("frequency" => 20, "confidence" => 99)
      SiteSetting.spam_warden_preset = "balanced"
      expect(assess({ "email" => strong })).to include("score" => 100, "decision" => "silence")
      expect(assess({ "email" => strong }, reading: -15)["decision"]).to eq("review")
      SiteSetting.spam_warden_email_report_points = 0
      expect(assess({ "email" => strong })).to include("score" => 0, "decision" => "silence")
      expect(assess({ "email" => match.merge("confidence" => 50) })["decision"]).to eq("review")
    end

    it "adds confirmed spam after flooring suspicion without discounting it for reading" do
      SiteSetting.spam_warden_local_points_cap = 0
      [1, 2].each do |count|
        result =
          assess(
            {},
            reading: -15,
            local: {
              "posting_points" => 0,
              "history_points" => count * 85,
              "confirmed_spam_posts" => count,
            },
          )
        expect(result).to include("score" => [85 * count, 100].min, "decision" => "review")
        expect(result["calculation"]).to include(
          "suspicion" => 0,
          "confirmed" => count * 85,
          "reading" => -15,
        )
      end
    end
  end

  describe "local signal assessment" do
    it "requests review for combined posting evidence even with positive reading" do
      assessment =
        described_class.assess(
          {},
          described_class.settings,
          engagement: {
            "adjustment" => -30,
          },
          local_signals: {
            "adjustment" => 25,
          },
          status: "checked",
        )

      expect(assessment).to include(
        "score" => 0,
        "decision" => "review",
        "external_decision" => "allow",
      )
    end

    it "treats an isolated posting signal as watch and never silences on local evidence" do
      { 15 => "watch", 20 => "watch", 25 => "review", 50 => "review" }.each do |points, decision|
        assessment =
          described_class.assess(
            {},
            described_class.settings,
            engagement: {
              "adjustment" => 0,
            },
            local_signals: {
              "adjustment" => points,
            },
            status: "checked",
          )

        expect(assessment).to include("score" => points, "decision" => decision)
      end
    end

    it "cannot use local points to reverse reading's reduction of a silence recommendation" do
      evidence =
        %w[email ip].index_with do
          {
            "appears" => true,
            "frequency" => 20,
            "confidence" => 99,
            "last_seen" => 1.day.ago.iso8601,
          }
        end
      assessment =
        described_class.assess(
          evidence,
          described_class.settings,
          engagement: {
            "adjustment" => -30,
          },
          local_signals: {
            "adjustment" => 50,
          },
          status: "checked",
        )

      expect(assessment).to include("score" => 100, "decision" => "review")
    end

    it "permits local review during an unavailable lookup without a risk percentage" do
      assessment =
        described_class.assess(
          {},
          described_class.settings,
          engagement: {
            "adjustment" => 0,
          },
          local_signals: {
            "adjustment" => 50,
          },
          status: "unknown",
        )

      expect(assessment).to include("score" => nil, "scored" => false, "decision" => "review")
    end
  end

  describe ".evaluate" do
    let(:strong) do
      {
        "appears" => true,
        "frequency" => 20,
        "confidence" => 99,
        "last_seen" => 1.day.ago.iso8601,
        "blacklisted" => false,
      }
    end

    it "allows accounts without matches" do
      expect(described_class.evaluate({})).to eq("allow")
    end

    it "requires corroboration to recommend silencing with the conservative preset" do
      expect(described_class.evaluate("email" => strong)).to eq("review")
      expect(described_class.evaluate("email" => strong, "ip" => strong)).to eq("silence")
    end

    it "accepts strong email evidence alone with the balanced preset" do
      SiteSetting.spam_warden_preset = "balanced"

      expect(described_class.evaluate("email" => strong)).to eq("silence")
      expect(described_class.evaluate("ip" => strong)).to eq("review")
    end

    it "treats username matches as informational" do
      expect(described_class.evaluate("username" => strong)).to eq("watch")
    end

    it "requires recent, sufficiently frequent, confident exact matches" do
      [
        { "last_seen" => 31.days.ago.iso8601 },
        { "last_seen" => 1.day.from_now.iso8601 },
        { "last_seen" => nil },
        { "frequency" => 1 },
        { "confidence" => 49 },
        { "confidence" => nil },
        { "blacklisted" => true },
      ].each do |weakness|
        expect(described_class.evaluate("email" => strong.merge(weakness))).to eq("watch")
      end
    end
  end
end
