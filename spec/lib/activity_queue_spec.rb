# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::ActivityQueue do
  fab!(:user)

  before { Jobs.run_later! }

  it "combines a burst of events into one queued job" do
    expect { 20.times { described_class.enqueue(user.id) } }.to change(
      Jobs::SpamWardenCheck.jobs,
      :size,
    ).by(1)
  end

  it "permits a follow-up once the worker starts without letting an old worker release a new reservation" do
    described_class.enqueue(user.id)
    first_token = Jobs::SpamWardenCheck.jobs.last["args"].first["activity_token"]
    described_class.release(user.id, first_token)
    described_class.enqueue(user.id)
    described_class.release(user.id, first_token)

    expect { described_class.enqueue(user.id) }.not_to change(Jobs::SpamWardenCheck.jobs, :size)
    expect(Jobs::SpamWardenCheck.jobs.last["args"].first["activity_token"]).not_to eq(first_token)
  end

  it "does not reserve or enqueue rolled-back activity" do
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        described_class.enqueue(user.id)
        raise ActiveRecord::Rollback
      end
    end.not_to change(Jobs::SpamWardenCheck.jobs, :size)

    expect { described_class.enqueue(user.id) }.to change(Jobs::SpamWardenCheck.jobs, :size).by(1)
  end

  it "releases the reservation if pushing the job fails" do
    Jobs.stubs(:enqueue_in).raises(IOError)
    expect { described_class.enqueue(user.id) }.to raise_error(IOError)
    Jobs.unstub(:enqueue_in)

    expect { described_class.enqueue(user.id) }.to change(Jobs::SpamWardenCheck.jobs, :size).by(1)
  end
end
