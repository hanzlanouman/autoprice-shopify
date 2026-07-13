require "rails_helper"

RSpec.describe Pricing::Recommender do
  describe ".for_environment" do
    it "uses Gemini when its API key is configured" do
      allow(Gemini::Client).to receive(:configured?).and_return(true)
      allow(Gemini::Client).to receive(:new).and_return(instance_double(Gemini::Client))

      expect(described_class.for_environment).to be_a(Pricing::Recommender::Gemini)
    end

    it "fails safely instead of silently formula-pricing a live store without Gemini" do
      allow(Gemini::Client).to receive(:configured?).and_return(false)
      allow(Shopify::Client).to receive(:configured?).and_return(true)

      expect(described_class.for_environment).to be_a(Pricing::Recommender::Unavailable)
    end

    it "uses the deterministic engine for the credential-free local demo" do
      allow(Gemini::Client).to receive(:configured?).and_return(false)
      allow(Shopify::Client).to receive(:configured?).and_return(false)

      expect(described_class.for_environment).to be_a(Pricing::Recommender::Deterministic)
    end
  end
end
