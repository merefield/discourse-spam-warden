# frozen_string_literal: true

RSpec.describe MiniScheduler::Manager do
  it "drains persisted legacy schedules once and continues scheduling Warden jobs" do
    manager = described_class.without_runner
    manager.redis = Discourse.redis
    manager.queue = "spam_warden_legacy_spec"
    dispatched = Queue.new
    manager.instance_variable_set(:@runner, dispatched)
    queue_key = described_class.queue_key(manager.queue)

    [Jobs::SpamGuardCleanup, Jobs::SpamGuardSubmissionRecovery].each do |legacy|
      manager.redis.zadd(queue_key, 1.minute.ago.to_i, legacy.name)

      manager.tick

      expect(dispatched.pop(true)).to eq(legacy)
      expect(manager.redis.zrange(queue_key, 0, -1)).not_to include(legacy.name)
      expect(legacy.scheduled?).to eq(false)
    end

    [Jobs::SpamWardenCleanup, Jobs::SpamWardenSubmissionRecovery].each do |current|
      manager.ensure_schedule!(current)
      expect(manager.redis.zrange(queue_key, 0, -1)).to include(current.name)
      expect(current.scheduled?).to eq(true)
    end
  end
end
