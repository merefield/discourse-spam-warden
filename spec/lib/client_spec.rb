# frozen_string_literal: true

RSpec.describe DiscourseSpamWarden::Client do
  describe "#lookup" do
    let(:fields) { { "email" => "person@example.com", "ip" => "8.8.8.8" } }
    let(:response_body) do
      {
        success: 1,
        email: {
          appears: 1,
          frequency: 20,
          confidence: 99,
          lastseen: "2026-01-01 00:00:00",
          value: fields["email"],
        },
        ip: {
          appears: 0,
          frequency: 0,
          value: fields["ip"],
        },
      }
    end

    it "combines identifiers in an HTTPS POST and caches only normalized evidence" do
      request =
        stub_request(:post, "https://api.stopforumspam.org/api").with(
          body: hash_including(fields),
        ).to_return(body: response_body.to_json)

      result = described_class.new.lookup(fields)
      expect(result["status"]).to eq("checked")
      expect(result["evidence"]["email"]).to include("frequency" => 20, "confidence" => 99)
      expect(result.to_json).not_to include(*fields.values)
      expect(described_class.new.lookup(fields)).to eq(result)
      expect(request).to have_been_requested.once
      expect(described_class.health["status"]).to eq("healthy")
    end

    it "records unknown status for malformed results and opens the circuit" do
      request = stub_request(:post, "https://api.stopforumspam.org/api").to_return(body: "not json")

      expect(described_class.new.lookup(fields)).to include(
        "status" => "unknown",
        "error_code" => "invalid_response",
      )
      expect(described_class.new.lookup(fields)).to include(
        "status" => "unknown",
        "error_code" => "circuit_open",
      )
      expect(request).to have_been_requested.once
      expect(described_class.health["status"]).to eq("degraded")
    end

    it "releases provider capacity after a successful lookup" do
      request =
        stub_request(:post, "https://api.stopforumspam.org/api").to_return(
          body: response_body.to_json,
        )

      described_class.new.lookup(fields)

      expect(described_class.new.lookup(fields, bypass_cache: true)["status"]).to eq("checked")
      expect(request).to have_been_requested.twice
    end

    it "fails open on a timeout" do
      stub_request(:post, "https://api.stopforumspam.org/api").to_timeout

      expect(described_class.new.lookup(fields)).to include("status" => "unknown", "evidence" => {})
    end

    it "rejects missing fields and invalid confidence instead of treating them as clean" do
      stub_request(:post, "https://api.stopforumspam.org/api").to_return(
        body: response_body.deep_merge(email: { confidence: 101 }).to_json,
      )

      expect(described_class.new.lookup(fields)["status"]).to eq("unknown")
    end

    it "skips requests when no identifiers are available" do
      expect(described_class.new.lookup({})).to include("status" => "skipped")
    end
  end

  describe ".identifiers" do
    fab!(:user)

    it "keeps private and loopback addresses local" do
      %w[127.0.0.1 192.168.1.1 ::1 fd00::1].each do |address|
        user.registration_ip_address = address
        expect(described_class.identifiers(user)).to eq("email" => user.email)
      end
    end
  end
end
