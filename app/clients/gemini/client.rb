require "faraday"
require "faraday/retry"

module Gemini
  # The only HTTP-aware code for Gemini. Calls generateContent with a strict
  # responseSchema (structured JSON out), retries transient failures with
  # backoff, and returns parsed JSON — mapping every failure to Gemini::Error
  # (docs/ARCHITECTURE.md).
  class Client
    BASE_URL = "https://generativelanguage.googleapis.com/v1beta".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30

    attr_reader :last_usage_metadata

    def self.configured?
      ENV["GEMINI_API_KEY"].present?
    end

    def initialize(api_key: ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_MODEL", "gemini-3.5-flash"))
      @api_key = api_key
      @model = model
      raise Unavailable, "GEMINI_API_KEY is not set" if @api_key.blank?
    end

    # prompt: String, schema: Hash (responseSchema). Returns parsed JSON (Array
    # or Hash) from the model, or raises Gemini::Unavailable.
    def generate_json(prompt, schema:, temperature: 0.2)
      response = connection.post("models/#{@model}:generateContent") do |req|
        req.body = request_body(prompt, schema, temperature).to_json
      end
      handle(response)
    rescue Faraday::Error => e
      raise Unavailable, "Gemini transport error: #{e.message}"
    end

    private

    def request_body(prompt, schema, temperature)
      {
        contents: [ { parts: [ { text: prompt } ] } ],
        generationConfig: {
          temperature: temperature,
          responseMimeType: "application/json",
          responseSchema: schema
        }
      }
    end

    def handle(response)
      raise Unavailable, "Gemini returned #{response.status}" unless response.status == 200

      payload = JSON.parse(response.body)
      @last_usage_metadata = payload["usageMetadata"] || {}
      text = payload.dig("candidates", 0, "content", "parts", 0, "text")
      raise Unavailable, "Gemini returned no content" if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError => e
      raise MalformedResponse, "Gemini returned unparseable JSON: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |f|
        f.request :retry,
                  max: 3,
                  methods: %i[post],
                  interval: 0.5,
                  backoff_factor: 2,
                  retry_statuses: [ 429, 500, 502, 503, 504 ],
                  exceptions: [
                    Faraday::TimeoutError,
                    Faraday::ConnectionFailed,
                    Faraday::RetriableResponse
                  ]
        f.headers["Content-Type"] = "application/json"
        f.headers["x-goog-api-key"] = @api_key
        f.options.timeout = READ_TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
