# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::AdditionalEvidence do
  fab!(:user)
  let(:plugin) { Plugin::Instance.new }
  let(:entries) { [{ "label" => "Extension evidence", "points" => 25 }] }
  let(:modifier) { proc { |_value, _user_id, _source| entries } }

  before do
    SiteSetting.spam_warden_enabled = true
    plugin.stubs(:enabled?).returns(true)
    SiteSetting.spam_warden_mode = "protect"
    SiteSetting.spam_warden_check_ip = false
    DiscoursePluginRegistry.register_modifier(plugin, :spam_warden_additional_evidence, &modifier)
    stub_request(:post, "https://api.stopforumspam.org/api").to_return(
      body: { success: 1, email: { appears: 0, frequency: 0 } }.to_json,
    )
  end

  after do
    DiscoursePluginRegistry.unregister_modifier(plugin, :spam_warden_additional_evidence, &modifier)
  end

  it "persists extension evidence before assessment and only requests review" do
    scan = DiscourseSpamWarden::Checker.call(user, source: "registration")
    expect(scan).to have_attributes(decision: "review", action_taken: "review")
    expect(scan.policy.dig("assessment", "additional_evidence")).to eq(entries)
    expect(user.reload).not_to be_silenced
  end

  it "ignores disabled extensions and preserves account exemptions" do
    plugin.stubs(:enabled?).returns(false)
    scan = DiscourseSpamWarden::Checker.call(user, source: "manual")
    expect(scan.policy.dig("assessment", "additional_evidence")).to eq([])
    DiscourseSpamWarden::Account.create!(user: user, allowed: true)
    plugin.stubs(:enabled?).returns(true)
    expect { DiscourseSpamWarden::Checker.call(user, source: "manual") }.not_to change(
      DiscourseSpamWarden::Scan,
      :count,
    )
  end

  context "with invalid or oversized contributions" do
    let(:entries) do
      [
        nil,
        { "label" => "Invalid", "points" => -20 },
        { "label" => "x" * 201, "points" => 25 },
        { "label" => "Valid", "points" => 25, "email" => user.email },
      ]
    end

    it "retains only bounded display evidence" do
      expect(described_class.collect(user_id: user.id, source: "manual")).to eq(
        [{ "label" => "Valid", "points" => 25 }],
      )
    end
  end

  context "when an extension fails" do
    let(:modifier) { proc { raise "unavailable" } }

    it "continues the free check without extension evidence" do
      scan = DiscourseSpamWarden::Checker.call(user, source: "registration")
      expect(scan).to have_attributes(status: "checked", decision: "allow", action_taken: "none")
      expect(scan.policy.dig("assessment", "additional_evidence")).to eq([])
    end
  end
end
