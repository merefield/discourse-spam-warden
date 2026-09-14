# frozen_string_literal: true

RSpec.describe DiscourseSpamGuard::SubmissionClient do
  describe "#submit" do
    let(:payload) do
      {
        "username" => "test",
        "email" => "spam+tag@example.com",
        "ip_addr" => "8.8.4.4",
        "evidence" => "a&b=1\nhttps://example.com/?x=2",
      }
    end

    before { SiteSetting.spam_guard_submission_api_key = "secret&key" }

    it "form-encodes identifiers, evidence and credentials and accepts JSON success" do
      request =
        stub_request(:post, described_class::ENDPOINT).with(
          body: payload.merge("api_key" => "secret&key", "f" => "json"),
        ).to_return(body: '{"success":1}')
      expect(described_class.new.submit(payload)).to eq(["submitted", nil])
      expect(request).to have_been_requested.once
    end

    it "accepts the documented empty HTTP 200 success response" do
      ["", " \r\n"].each do |body|
        stub_request(:post, described_class::ENDPOINT).to_return(status: 200, body: body)
        expect(described_class.new.submit(payload)).to eq(["submitted", nil])
      end
    end

    it "keeps empty error responses uncertain" do
      [403, 503].each do |status|
        stub_request(:post, described_class::ENDPOINT).to_return(status: status, body: "")
        expect(described_class.new.submit(payload)).to eq(%w[unknown http_error])
      end
    end

    it "distinguishes rejection from ambiguous or oversized replies without retaining raw errors" do
      ['{"success":0,"error":"sensitive text"}', "{}", "<html>OK</html>", "x" * 16_385].zip(
        %w[rejected unknown unknown unknown],
      )
        .each do |body, status|
          stub_request(:post, described_class::ENDPOINT).to_return(body: body)
          result = described_class.new.submit(payload)
          expect(result.first).to eq(status)
          expect(result.last).not_to include(body)
        end
    end

    it "does not follow redirects" do
      stub_request(:post, described_class::ENDPOINT).to_return(
        status: 302,
        headers: {
          "Location" => "https://example.com/collect",
        },
      )
      expect(described_class.new.submit(payload)).to eq(%w[unknown http_error])
      expect(a_request(:any, "https://example.com/collect")).not_to have_been_made
    end

    it "only retries connection failures before sending" do
      stub_request(:post, described_class::ENDPOINT).to_raise(Net::OpenTimeout)
      expect(described_class.new.submit(payload)).to eq(%w[pending connection_failed])
      stub_request(:post, described_class::ENDPOINT).to_raise(Net::ReadTimeout)
      expect(described_class.new.submit(payload)).to eq(%w[unknown delivery_uncertain])
    end
  end
end
