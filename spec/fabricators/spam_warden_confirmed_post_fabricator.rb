# frozen_string_literal: true

Fabricator(:spam_warden_confirmed_post, from: :post) do
  after_create do |post|
    post.user.email_tokens.update_all(confirmed: true)
    post.user.update!(registration_ip_address: "8.8.4.4")
    review =
      Fabricate(
        :reviewable_flagged_post,
        target: post,
        target_created_by: post.user,
        status: :approved,
        reviewable_scores: [],
      )
    Fabricate(
      :reviewable_score,
      reviewable: review,
      reviewable_score_type: ReviewableScore.types[:spam],
      reviewed_by: Fabricate(:admin),
      reviewed_at: 1.minute.ago,
      status: :agreed,
    )
  end
end
