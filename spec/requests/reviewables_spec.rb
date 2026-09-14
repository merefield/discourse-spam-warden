# frozen_string_literal: true

RSpec.describe ReviewablesController do
  fab!(:admin)

  before { SiteSetting.spam_warden_enabled = true }

  it "loads all scan evidence in one query and reuses core's preloaded users" do
    scans =
      3.times.map do
        user = Fabricate(:user)
        review =
          ReviewableSpamWarden.needs_review!(
            target: user,
            created_by: Discourse.system_user,
            target_created_by: user,
          )
        review.add_score(
          Discourse.system_user,
          ReviewableScore.types[:needs_approval],
          reason: "spam_warden",
          force_review: true,
        )
        scan =
          DiscourseSpamWarden::Scan.create!(
            user: user,
            source: "manual",
            status: "checked",
            decision: "review",
            reviewable: review,
          )
        review.update!(payload: { "scan_id" => scan.id })
        scan
      end
    sign_in(admin)
    queries = track_sql_queries { get "/review.json", params: { type: "ReviewableSpamWarden" } }

    expect(response.status).to eq(200)
    evidence =
      response.parsed_body.fetch("reviewables").map { |review| review.fetch("spam_warden_scan") }
    expect(evidence.map { |scan| scan["id"] }).to match_array(scans.map(&:id))
    expect(evidence.map { |scan| scan["username"] }).to match_array(
      scans.map { |scan| scan.user.username },
    )
    expect(queries.count { |sql| sql.include?("FROM \"spam_warden_scans\"") }).to eq(1)

    page = Reviewable.list_for(admin, type: "ReviewableSpamWarden", limit: 1)
    count_queries = track_sql_queries { expect(page.count).to eq(1) }
    expect(count_queries.grep(/FROM "spam_warden_scans"/)).to be_empty

    page_queries =
      track_sql_queries do
        expect(page.to_a.size).to eq(1)
        expect(page.to_a.first.spam_warden_scan).to be_present
      end
    expect(page_queries.grep(/FROM "spam_warden_scans"/).size).to eq(1)

    get "/review/#{scans.first.reviewable_id}.json"
    expect(response.status).to eq(200)
    expect(response.parsed_body.dig("reviewable", "spam_warden_scan", "id")).to eq(scans.first.id)
  end
end
