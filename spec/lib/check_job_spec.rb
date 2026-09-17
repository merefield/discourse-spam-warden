# frozen_string_literal: true

RSpec.describe Jobs::SpamWardenCheck do
  describe "#execute" do
    fab!(:user)

    before do
      SiteSetting.spam_warden_enabled = true
      SiteSetting.spam_warden_check_ip = false
      Jobs.run_later!
    end

    it "retries unavailable lookups with a bounded delay" do
      freeze_time
      stub_request(:post, "https://api.stopforumspam.org/api").to_timeout

      expect_enqueued_with(
        job: :spam_warden_check,
        args: {
          user_id: user.id,
          source: "registration",
          attempt: 1,
        },
        at: 1.minute.from_now,
      ) { described_class.new.execute(user_id: user.id, source: "registration") }
    end

    it "stops retrying after the final attempt" do
      stub_request(:post, "https://api.stopforumspam.org/api").to_timeout

      expect_not_enqueued_with(job: :spam_warden_check) do
        described_class.new.execute(user_id: user.id, source: "registration", attempt: 2)
      end
    end

    it "does not duplicate a successful registration check" do
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )

      described_class.new.execute(user_id: user.id, source: "registration")

      expect {
        described_class.new.execute(user_id: user.id, source: "registration")
      }.not_to change(DiscourseSpamWarden::Scan, :count)
    end

    it "preserves a follow-up when an activity job encounters the execution cooldown" do
      freeze_time
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
      )
      DiscourseSpamWarden::Checker.call(user, source: "activity")
      freeze_time 10.seconds.from_now

      expect_enqueued_with(
        job: :spam_warden_check,
        args: {
          user_id: user.id,
          source: "activity",
        },
        at: 1.minute.from_now,
      ) { described_class.new.execute(user_id: user.id, source: "activity") }
    end

    it "bounds activity outage retries even when the previous scan was reused" do
      freeze_time
      stub_request(:post, "https://api.stopforumspam.org/api").to_timeout
      DiscourseSpamWarden::Checker.call(user, source: "activity")
      freeze_time 10.seconds.from_now

      expect_not_enqueued_with(job: :spam_warden_check) do
        described_class.new.execute(user_id: user.id, source: "activity", attempt: 2)
      end
    end
  end
end
