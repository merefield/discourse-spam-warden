# frozen_string_literal: true

RSpec.describe ReviewableSpamWarden do
  fab!(:admin)
  fab!(:moderator)
  fab!(:user)
  let(:review) do
    described_class.needs_review!(
      target: user,
      created_by: Discourse.system_user,
      target_created_by: user,
    )
  end

  before { SiteSetting.spam_warden_enabled = true }

  it "offers persistent exemptions only to admins while retaining moderator silence actions" do
    expect(review.actions_for(admin.guardian).has?(:allow_account)).to eq(true)
    expect(review.actions_for(moderator.guardian).has?(:allow_account)).to eq(false)
    expect(review.actions_for(moderator.guardian).has?(:silence_account)).to eq(true)

    expect { review.perform(moderator, :allow_account) }.to raise_error(Reviewable::InvalidAction)
    expect(review.reload).to be_pending
    expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty

    expect(review.perform(moderator, :silence_account)).to be_success
    expect(user.reload).to be_silenced
  end

  it "records a staff decision without attributing it to external reputation" do
    result = review.perform(admin, :silence_account)

    expect(result).to be_success
    expect(user.reload).to be_silenced
    expect(user.silence_reason).to eq(
      I18n.t("spam_warden.manual_silence_reason", reviewable_id: review.id),
    )
    expect(review.reload).to be_rejected
  end

  it "requires a distinct confirmation for an existing staff restriction" do
    UserSilencer.new(user, admin, reason: "Independent decision").silence
    history_id = UserHistory.where(target_user_id: user.id).maximum(:id)

    expect(review.perform(admin, :confirm_restriction)).to be_success
    expect(user.reload.silence_reason).to eq("Independent decision")
    expect(UserHistory.where(target_user_id: user.id).maximum(:id)).to eq(history_id)
    expect(DiscourseSpamWarden::Account.where(user: user)).to be_empty
  end

  it "leaves the review pending if a restriction disappears before confirmation" do
    result = review.perform_confirm_restriction(admin, {})

    expect(result).not_to be_success
    expect(result.errors.full_messages).to include(I18n.t("spam_warden.silence_failed"))
    expect(review.reload).to be_pending
  end

  it "reports failure if a concurrent restriction prevents the requested silence" do
    UserSilencer.new(user, admin, reason: "Independent decision").silence

    result = review.perform_silence_account(admin, {})

    expect(result).not_to be_success
    expect(review.reload).to be_pending
    expect(user.reload.silence_reason).to eq("Independent decision")
  end
end
