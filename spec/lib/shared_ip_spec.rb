# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::SharedIp do
  fab!(:user) do
    Fabricate(:user, ip_address: "203.0.113.10", registration_ip_address: "203.0.113.10")
  end
  fab!(:peer) do
    Fabricate(:user, ip_address: "203.0.113.10", registration_ip_address: "203.0.113.10")
  end

  def assessment(email: 0, ip: 0, shared: 0)
    {
      "scored" => true,
      "external_scoring" => {
        "points" => {
          "email" => email,
          "ip" => ip,
        },
      },
      "calculation" => {
        "posting" => 0,
        "additional" => 0,
        "reading" => 0,
        "confirmed" => 0,
        "shared_ip" => shared,
        "local_cap" => 100,
      },
    }
  end

  def record(target, evidence, created_at: Time.current)
    DiscourseSpamWarden::Scan.create!(
      user: target,
      source: "manual",
      status: "checked",
      decision: "watch",
      evidence: {
      },
      policy: {
        "assessment" => evidence,
      },
      created_at: created_at,
    )
  end

  it "includes the independently suspicious account itself and all direct peers" do
    own = assessment(email: 40)
    expect(described_class.snapshot(user, own)).to include(
      "points" => 15,
      "related_accounts" => 1,
      "suspicious_accounts" => 1,
    )
    record(user, own)
    expect(described_class.snapshot(peer, assessment)).to include(
      "points" => 15,
      "related_accounts" => 1,
    )
    peer.update!(ip_address: "203.0.113.11", registration_ip_address: "203.0.113.11")
    expect(described_class.snapshot(user, own)["points"]).to eq(0)
  end

  it "excludes IP reputation and shared-IP points from independent suspicion" do
    record(user, assessment(ip: 100, shared: 100))
    expect(described_class.snapshot(peer, assessment(ip: 100, shared: 100))["points"]).to eq(0)
    expect(described_class.independent_score(assessment(email: 30, ip: 100, shared: 100))).to eq(30)
  end

  it "uses only the newest recent assessment and excludes allowed accounts" do
    record(user, assessment(email: 40), created_at: 1.hour.ago)
    record(user, assessment)
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(0)
    record(user, assessment(email: 40))
    DiscourseSpamWarden::Account.create!(user: user, allowed: true)
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(0)
  end

  it "matches registration and retained access history while respecting recency" do
    peer.update!(ip_address: "203.0.113.11", registration_ip_address: "203.0.113.11")
    history = UserIpAddressHistory.create!(user: peer, ip_address: user.ip_address)
    record(user, assessment(email: 40))
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(15)
    history.update!(updated_at: 31.days.ago)
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(0)
    peer.update!(registration_ip_address: user.ip_address)
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(15)
    SiteSetting.spam_warden_shared_ip_points = 0
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(0)
  end

  it "does not propagate suspicion through an unrelated second IP group" do
    record(user, assessment(email: 40))
    peer.update!(ip_address: "203.0.113.11")
    record(peer, assessment(shared: 15))
    third = Fabricate(:user, ip_address: "203.0.113.11", registration_ip_address: "203.0.113.11")
    expect(described_class.snapshot(peer, assessment)["points"]).to eq(15)
    expect(described_class.snapshot(third, assessment)["points"]).to eq(0)
  end
end
