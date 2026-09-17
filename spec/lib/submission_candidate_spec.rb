# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::SubmissionCandidate do
  fab!(:user)
  fab!(:admin)
  fab!(:post) { Fabricate(:spam_warden_confirmed_post, user: user) }

  describe ".latest" do
    it "includes retained public spam with the registration IP and bounded evidence" do
      post.update!(deleted_at: Time.current, raw: "spam & evidence " * 300)
      candidate = described_class.latest(user)
      expect(candidate.payload).to include(
        "email" => user.email,
        "username" => user.username,
        "ip_addr" => user.registration_ip_address.to_s,
      )
      expect(candidate.payload["evidence"]).to eq(
        "#{Discourse.base_url}/t/#{post.topic_id}/#{post.post_number}\n\n#{post.raw.first(2000)}",
      )
    end

    it "excludes accounts without independently confirmed spam" do
      expect(described_class.latest(Fabricate(:user))).to be_nil
      ReviewableFlaggedPost
        .find_by!(target: post)
        .reviewable_scores
        .update_all(status: ReviewableScore.statuses[:pending])
      expect(described_class.latest(user)).to be_nil
    end

    it "excludes automated and non-staff confirmation" do
      [Discourse.system_user, user].each do |reviewer|
        ReviewableFlaggedPost
          .find_by!(target: post)
          .reviewable_scores
          .update_all(reviewed_by_id: reviewer.id)
        expect(described_class.latest(user)).to be_nil
      end
    end

    it "excludes private topics and restricted categories" do
      post.topic.update!(archetype: Archetype.private_message, category_id: nil)
      expect(described_class.latest(user)).to be_nil
      post.topic.update!(
        archetype: Archetype.default,
        category: Fabricate(:category, read_restricted: true),
      )
      expect(described_class.latest(user)).to be_nil
    end

    it "excludes staff, inactive, staged and unconfirmed accounts" do
      [
        { admin: true },
        { moderator: true },
        { active: false },
        { staged: true },
      ].each do |attributes|
        user.assign_attributes(attributes)
        expect(described_class.latest(user)).to be_nil
        user.reload
      end
      user.email_tokens.update_all(confirmed: false)
      expect(described_class.latest(user)).to be_nil
    end

    it "excludes exempt accounts and posts with private addresses" do
      user.update!(registration_ip_address: "192.168.1.5")
      expect(described_class.latest(user)).to be_nil
      user.update!(registration_ip_address: "8.8.4.4")
      DiscourseSpamWarden::Moderation.allow(user, admin)
      expect(described_class.latest(user)).to be_nil
    end
  end

  describe ".public_ip?" do
    it "rejects non-public IPv4 and IPv4-mapped addresses" do
      %w[
        0.0.0.0
        0.1.2.3
        10.0.0.1
        100.64.0.1
        100.127.255.255
        127.0.0.1
        169.254.1.1
        172.16.0.1
        192.0.0.1
        192.0.2.1
        192.88.99.1
        192.168.1.1
        198.18.0.1
        198.51.100.1
        203.0.113.1
        224.0.0.1
        239.255.255.255
        240.0.0.1
        255.255.255.255
      ].each do |address|
        expect(described_class.public_ip?(address)).to eq(false), address
        expect(described_class.public_ip?("::ffff:#{address}")).to eq(false), address
      end
    end

    it "rejects non-public and transitional IPv6 addresses" do
      %w[
        ::
        ::1
        ::192.0.2.1
        64:ff9b::c000:201
        64:ff9b:1::1
        100::1
        100:0:0:1::1
        2001::1
        2001:2::1
        2001:db8::1
        2002:c000:201::1
        3fff::1
        5f00::1
        fc00::1
        fd00::1
        fe80::1
        fec0::1
        ff02::1
      ].each { |address| expect(described_class.public_ip?(address)).to eq(false), address }
      [nil, "", "not-an-ip"].each do |address|
        expect(described_class.public_ip?(address)).to eq(false)
      end
    end

    it "accepts ordinary public addresses and respects core network exclusions" do
      %w[
        8.8.4.4
        1.1.1.1
        100.63.255.255
        100.128.0.1
        ::ffff:8.8.4.4
        2001:4860:4860::8888
        2606:4700:4700::1111
      ].each { |address| expect(described_class.public_ip?(address)).to eq(true), address }
      SiteSetting.blocked_ip_blocks = "8.8.4.4"
      expect(described_class.public_ip?("8.8.4.4")).to eq(false)
    end

    it "does not offer a report for a special-purpose registration address" do
      user.update!(registration_ip_address: "100.64.0.1")
      expect(described_class.latest(user)).to be_nil
    end
  end

  describe ".from_token" do
    it "binds preview approval to the actor, target, content and expiration" do
      freeze_time
      token = described_class.latest(user).preview_token(admin)
      expect(described_class.from_token(user, admin, token).post.id).to eq(post.id)
      expect(described_class.from_token(user, Fabricate(:admin), token)).to be_nil
      expect(described_class.from_token(Fabricate(:user), admin, token)).to be_nil
      expect(described_class.from_token(user, admin, token + "tampered")).to be_nil
      post.update!(raw: "This evidence was changed after the administrator previewed it.")
      expect(described_class.from_token(user, admin, token)).to be_nil
      token = described_class.latest(user).preview_token(admin)
      freeze_time 11.minutes.from_now
      expect(described_class.from_token(user, admin, token)).to be_nil
    end
  end
end
