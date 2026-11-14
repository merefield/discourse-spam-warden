# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::AdminController do
  fab!(:admin)
  fab!(:user) do
    Fabricate(:user, registration_ip_address: "203.0.113.8", ip_address: "203.0.113.8")
  end
  fab!(:peer) do
    Fabricate(:user, registration_ip_address: "203.0.113.9", ip_address: "203.0.113.8")
  end

  it "restricts connection identifiers to admins, including when lookup is disabled" do
    get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
    expect(response.status).to eq(404)
    [Fabricate(:user), Fabricate(:moderator)].each do |actor|
      sign_in(actor)
      get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
      expect(response.status).to eq(404)
      expect(response.body).not_to include(user.ip_address.to_s)
    end
    sign_in(admin)
    get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
    expect(response.status).to eq(200)
    data = response.parsed_body
    expect(data["enabled"]).to eq(false)
    expect(data["total"]).to eq(1)
    expect(data["accounts"].sole).to include(
      "id" => peer.id,
      "independent_score" => nil,
      "qualifies" => false,
    )
    expect(data["accounts"].sole["connection_types"]).to include(
      "source" => "registration",
      "peer_source" => "latest_access",
    )
    expect(data["accounts"].sole["connections"].first["ip"]).to eq(user.ip_address.to_s)
  end

  it "shows saved points separately from current eligibility and clears deleted or exempt peers" do
    DiscourseSpamWarden::Scan.create!(
      user: user,
      status: "checked",
      decision: "watch",
      source: "manual",
      evidence: {
      },
      policy: {
        "assessment" => {
          "scored" => true,
          "external_scoring" => {
            "points" => {
              "email" => 40,
            },
          },
          "calculation" => {
            "local_cap" => 100,
          },
          "shared_ip" => {
            "points" => 15,
          },
        },
      },
    )
    sign_in(admin)
    get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
    expect(response.parsed_body).to include(
      "own_qualifies" => true,
      "own_score" => 40,
      "saved_points" => 15,
    )
    DiscourseSpamWarden::Account.create!(user: peer, allowed: true)
    get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
    expect(response.parsed_body).to include("total" => 0, "accounts" => [], "saved_points" => 15)
    DiscourseSpamWarden::Scan.where(user: user).update_all(created_at: 31.days.ago)
    get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
    expect(response.parsed_body).to include("own_score" => nil, "own_qualifies" => false)
  end

  it "paginates without losing matches and labels retained history separately" do
    peer.update!(ip_address: "203.0.113.9")
    history = UserIpAddressHistory.create!(user: peer, ip_address: user.ip_address)
    sign_in(admin)
    stub_const(DiscourseSpamWarden::SharedIpPresentation, :PAGE_SIZE, 1) do
      other = Fabricate(:user, registration_ip_address: user.ip_address)
      get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
      first = response.parsed_body
      expect(first["total"]).to eq(2)
      expect(first["accounts"].sole["connection_types"]).to include(
        "source" => "registration",
        "peer_source" => "retained_history",
      )
      get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json",
          params: {
            after_id: first["next_after_id"],
          }
      expect(response.parsed_body["accounts"].sole["id"]).to eq(other.id)
      expect(response.parsed_body["next_after_id"]).to be_nil
      history.destroy!
      get "/admin/plugins/discourse-spam-warden/accounts/#{user.id}/related.json"
      expect(response.parsed_body["total"]).to eq(1)
    end
  end
end
