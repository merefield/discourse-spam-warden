# frozen_string_literal: true

RSpec.describe SpamGuardSubmissionSerializer do
  it "resolves current usernames per event and preserves IDs for deleted actors" do
    admin = Fabricate(:admin)
    former_admin = Fabricate(:admin)
    events =
      [admin, former_admin].map { |actor| { "actor_id" => actor.id, "status" => "approved" } }
    submission = DiscourseSpamGuard::Submission.new(events: events)
    admin.update!(username: "renamed_admin")
    former_admin.destroy!

    result = described_class.new(submission, root: false).as_json[:events]

    expect(result).to eq(
      [
        events.first.merge("actor_username" => "renamed_admin"),
        events.last.merge("actor_username" => nil),
      ],
    )
    expect(submission.events).to eq(events)
  end
end
