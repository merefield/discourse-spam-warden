# frozen_string_literal: true

RSpec.describe "Report spam with lookups disabled" do
  fab!(:admin)
  fab!(:user)
  fab!(:spam_post) { Fabricate(:spam_warden_confirmed_post, user: user) }

  it "keeps the real admin connector and confirmation dialog available" do
    SiteSetting.spam_warden_enabled = false
    SiteSetting.spam_warden_submissions_enabled = true
    SiteSetting.spam_warden_submission_api_key = "private-test-key"
    sign_in(admin)

    visit "/admin/users/#{user.id}/#{user.username}"
    find(".spam-warden-user__toggle").click
    expect(page).to have_css(".spam-warden-submission__preview")
    find(".spam-warden-submission__preview").click
    expect(page).to have_css(".spam-warden-submission-confirmation", text: user.email)
    expect(page).to have_css(".spam-warden-submission-confirmation__evidence", text: spam_post.raw)
    find(".spam-warden-submission-confirmation__cancel").click
    expect(page).to have_no_css(".spam-warden-submission-confirmation")
    expect(DiscourseSpamWarden::Submission.where(user_id: user.id)).to be_empty
    expect(DiscourseSpamWarden::Scan.where(user_id: user.id)).to be_empty
  end
end
