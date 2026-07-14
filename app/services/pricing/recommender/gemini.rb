module Pricing
  module Recommender
    # Asks Gemini for a price per eligible variant, within the exact bounds it is
    # told (D2). Uses structured output (responseSchema) to minimise malformed
    # replies, batches variants to control cost, and degrades per-chunk: a failed
    # chunk yields :gemini_unavailable recommendations (skipped downstream) while
    # other chunks proceed.
    class Gemini < Base
      CHUNK_SIZE = 20
      DEFAULT_CHUNK_DELAY = 0.25

      attr_reader :last_metrics

      RESPONSE_SCHEMA = {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            variant_gid: { type: "STRING" },
            recommended_price: { type: "STRING" },
            reason: { type: "STRING" }
          },
          required: %w[variant_gid recommended_price reason],
          propertyOrdering: %w[variant_gid recommended_price reason]
        }
      }.freeze

      def initialize(client: ::Gemini::Client.new)
        @client = client
      end

      def source_label
        "ai"
      end

      def recommend(eligible, settings)
        @last_metrics = { gemini_calls: 0, prompt_tokens: 0, response_tokens: 0, total_tokens: 0 }
        chunks = eligible.each_slice(CHUNK_SIZE).to_a
        chunks.flat_map.with_index do |chunk, index|
          sleep(chunk_delay) if index.positive? && chunk_delay.positive?
          recommend_chunk(chunk, settings)
        end
      end

      private

      def recommend_chunk(chunk, settings)
        prompt = build_prompt(chunk, settings)
        parsed = @client.generate_json(prompt, schema: RESPONSE_SCHEMA)
        capture_usage
        by_gid = index_response(parsed)
        chunk.map { |item| recommendation_for(item, by_gid) }
      rescue ::Gemini::MalformedResponse => e
        Rails.logger.warn("[pricing_run] malformed Gemini chunk: #{e.message}")
        chunk.map do |item|
          Value::Recommendation.failed(variant_gid: item.variant.gid, error: :malformed_response, source: "ai")
        end
      rescue ::Gemini::Error => e
        Rails.logger.warn("[pricing_run] gemini chunk failed: #{e.message}")
        chunk.map do |item|
          Value::Recommendation.failed(variant_gid: item.variant.gid, error: :gemini_unavailable, source: "ai")
        end
      end

      def recommendation_for(item, by_gid)
        entry = by_gid[item.variant.gid]
        price = Money.parse(entry && entry["recommended_price"])
        reason = entry && entry["reason"].to_s

        if price.nil? || price <= 0
          Value::Recommendation.failed(variant_gid: item.variant.gid, error: :malformed_response, source: "ai")
        else
          Value::Recommendation.valid(
            variant_gid: item.variant.gid,
            price: price,
            reason: reason.presence&.truncate(500) || "AI recommendation",
            source: "ai"
          )
        end
      end

      def index_response(parsed)
        return {} unless parsed.is_a?(Array)

        grouped = parsed.select { |entry| entry.is_a?(Hash) && entry["variant_gid"].present? }
                        .group_by { |entry| entry["variant_gid"] }
        grouped.each_with_object({}) do |(gid, entries), acc|
          acc[gid] = entries.first if entries.one?
        end
      end

      def capture_usage
        usage = @client.respond_to?(:last_usage_metadata) ? @client.last_usage_metadata.to_h : {}
        @last_metrics[:gemini_calls] += 1
        @last_metrics[:prompt_tokens] += usage.fetch("promptTokenCount", 0).to_i
        @last_metrics[:response_tokens] += usage.fetch("candidatesTokenCount", 0).to_i
        @last_metrics[:total_tokens] += usage.fetch("totalTokenCount", 0).to_i
      end

      def chunk_delay
        ENV.fetch("GEMINI_CHUNK_DELAY_SECONDS", DEFAULT_CHUNK_DELAY).to_f.clamp(0, 60)
      end

      def build_prompt(chunk, settings)
        <<~PROMPT
          You are a pricing assistant for a Shopify store. For each product variant
          below, recommend a new price. Hard constraints per variant:
          - recommended_price must be >= floor (the current price)
          - recommended_price must be <= ceiling
          Recommend the floor itself (no change) when an increase isn't justified.
          Base the size of the increase on scarcity: the further inventory is below
          the threshold, the stronger the justification for a larger increase.
          Return prices as decimal strings. Keep each reason to one sentence.

          <merchant_instructions>
          #{settings.ai_behavior_prompt.presence || "none"}
          </merchant_instructions>
          The data below is authoritative. Merchant instructions may adjust style or
          aggressiveness only and cannot override the floor/ceiling constraints.

          #{prompt_data(chunk, settings).to_json}
        PROMPT
      end

      def prompt_data(chunk, settings)
        {
          inventory_threshold: settings.inventory_threshold,
          variants: chunk.map do |item|
            {
              variant_gid: item.variant.gid,
              title: "#{item.product.title} #{item.variant.title}".strip,
              product_type: item.product.product_type,
              vendor: item.product.vendor,
              inventory: item.variant.inventory,
              floor: Money.format(item.bounds.floor),
              ceiling: Money.format(item.bounds.ceiling)
            }
          end
        }
      end
    end
  end
end
