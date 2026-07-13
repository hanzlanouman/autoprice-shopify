require "rails_helper"

RSpec.describe Gemini::Client do
  let(:model) { "gemini-2.5-flash" }
  subject(:client) { described_class.new(api_key: "test-key", model: model) }
  let(:url) { "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent" }

  def stub_gemini(text:, status: 200)
    body = { candidates: [ { content: { parts: [ { text: text } ] } } ] }
    stub_request(:post, url).with(headers: { "X-Goog-Api-Key" => "test-key" })
                            .to_return(status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json)
  end

  it "raises Unavailable without an API key" do
    expect { described_class.new(api_key: nil) }.to raise_error(Gemini::Unavailable)
  end

  it "returns parsed JSON from the candidate text" do
    stub_gemini(text: [ { variant_gid: "v1", recommended_price: "12.00", reason: "r" } ].to_json)

    result = client.generate_json("prompt", schema: {})
    expect(result.first["variant_gid"]).to eq("v1")
  end

  it "sends structured-output generation config" do
    stub = stub_request(:post, url)
           .with(headers: { "X-Goog-Api-Key" => "test-key" }) do |req|
             JSON.parse(req.body).dig("generationConfig", "responseMimeType") == "application/json"
           end
           .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                      body: { candidates: [ { content: { parts: [ { text: "[]" } ] } } ] }.to_json)

    client.generate_json("prompt", schema: { type: "ARRAY" })
    expect(stub).to have_been_requested
  end

  it "maps a 500 to Unavailable" do
    stub_request(:post, url).with(headers: { "X-Goog-Api-Key" => "test-key" })
                            .to_return(status: 500, body: "{}")
    expect { client.generate_json("p", schema: {}) }.to raise_error(Gemini::Unavailable)
  end

  it "retries a transient POST and returns the recovered response" do
    request = stub_request(:post, url)
              .with(headers: { "X-Goog-Api-Key" => "test-key" })
              .to_return(
                { status: 503, body: "{}" },
                {
                  status: 200,
                  headers: { "Content-Type" => "application/json" },
                  body: { candidates: [ { content: { parts: [ { text: "[]" } ] } } ] }.to_json
                }
              )

    expect(client.generate_json("p", schema: {})).to eq([])
    expect(request).to have_been_requested.twice
  end

  it "raises MalformedResponse on unparseable candidate text" do
    stub_gemini(text: "not json {")
    expect { client.generate_json("p", schema: {}) }.to raise_error(Gemini::MalformedResponse, /unparseable/)
  end
end
