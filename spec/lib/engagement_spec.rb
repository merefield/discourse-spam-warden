# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Engagement do
  describe ".snapshot" do
    fab!(:user)

    before do
      freeze_time
      user.update!(created_at: Time.current)
      user.user_stat.update!(
        topics_entered: 0,
        posts_read_count: 0,
        time_read: 0,
        days_visited: 1,
        post_count: 0,
      )
    end

    it "treats zero reading as neutral at registration and shortly afterwards" do
      expect(described_class.snapshot(user, source: "registration")).to include(
        "adjustment" => 0,
        "level" => "new_account",
      )
      expect(described_class.snapshot(user, source: "manual")).to include("adjustment" => 0)
    end

    it "adds modest concern after an hour or after posting" do
      user.update!(created_at: 1.hour.ago)
      expect(described_class.snapshot(user, source: "recheck")).to include("adjustment" => 10)
      user.update!(created_at: Time.current)
      user.user_stat.update!(post_count: 1)
      expect(described_class.snapshot(user, source: "manual")).to include(
        "level" => "none",
        "adjustment" => 10,
      )
    end

    it "requires plausible reading time before granting more than minimal reassurance" do
      user.user_stat.update!(topics_entered: 100, posts_read_count: 1000, time_read: 0)
      expect(described_class.snapshot(user, source: "recheck")).to include(
        "level" => "limited",
        "adjustment" => -5,
      )
      user.user_stat.update!(time_read: 60)
      expect(described_class.snapshot(user, source: "recheck")).to include(
        "level" => "meaningful",
        "adjustment" => -10,
      )
    end

    it "caps reassurance and requires repeat visits for the strongest adjustment" do
      user.user_stat.update!(topics_entered: 5, posts_read_count: 30, time_read: 600)
      expect(described_class.snapshot(user, source: "recheck")).to include("adjustment" => -10)
      user.user_stat.update!(days_visited: 2)
      snapshot = described_class.snapshot(user, source: "recheck")
      expect(snapshot).to include(
        "level" => "sustained",
        "adjustment" => -15,
        "reading_minutes" => 10.0,
      )
      user.user_stat.update!(topics_entered: 1000, posts_read_count: 10_000, time_read: 100_000)
      expect(described_class.snapshot(user, source: "recheck")).to include("adjustment" => -15)
      expect(snapshot["topics_viewed"]).to eq(5)
    end

    it "treats missing statistics as unavailable rather than zero reading" do
      user.user_stat.destroy!
      expect(described_class.snapshot(user, source: "manual")).to include(
        "available" => false,
        "adjustment" => 0,
      )
    end

    it "uses the configured adjustment for each reading level" do
      SiteSetting.spam_warden_no_reading_adjustment = 7
      SiteSetting.spam_warden_reading_limited_adjustment = -2
      SiteSetting.spam_warden_reading_meaningful_adjustment = -8
      SiteSetting.spam_warden_reading_sustained_adjustment = -12
      user.update!(created_at: 2.hours.ago)
      expect(described_class.snapshot(user, source: "manual")["adjustment"]).to eq(7)
      user.user_stat.update!(posts_read_count: 1)
      expect(described_class.snapshot(user, source: "manual")["adjustment"]).to eq(-2)
      user.user_stat.update!(topics_entered: 1, posts_read_count: 3, time_read: 60)
      expect(described_class.snapshot(user, source: "manual")["adjustment"]).to eq(-8)
      user.user_stat.update!(
        topics_entered: 5,
        posts_read_count: 30,
        time_read: 600,
        days_visited: 2,
      )
      expect(described_class.snapshot(user, source: "manual")["adjustment"]).to eq(-12)
      SiteSetting.spam_warden_reading_sustained_adjustment = 0
      expect(described_class.snapshot(user, source: "manual")["adjustment"]).to eq(0)
    end
  end
end
