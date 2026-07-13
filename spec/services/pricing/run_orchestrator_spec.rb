require "rails_helper"

RSpec.describe Pricing::RunOrchestrator do
  subject(:orchestrator) do
    described_class.new(client: Shopify::LocalClient.new, recommender: Pricing::Recommender::Deterministic.new)
  end

  before { Setting.instance.update!(inventory_threshold: 10, max_price_percentage: BigDecimal("150.00")) }

  def cached_product(title:, price:, inventory:, **overrides)
    gid = "gid://shopify/Product/#{title.object_id}"
    create(
      :product,
      title: title,
      shopify_gid: gid,
      gift_card: overrides.fetch(:gift_card, false),
      variants: [ {
        gid: "#{gid}/v",
        title: "Default",
        price: price,
        inventory_quantity: inventory,
        tracked: overrides.fetch(:tracked, true),
        original_price: overrides[:original_price],
        last_written_price: overrides[:last_written_price],
        last_adjusted_at: overrides[:last_adjusted_at],
        inventory_at_last_adjustment: overrides[:inventory_at_last_adjustment]
      } ]
    )
  end

  def run!
    run = PricingRun.create!(status: "running", trigger: "manual", started_at: Time.current)
    orchestrator.call(run)
    run.reload
  end

  def variant_of(product)
    product.reload.variant_snapshots.first
  end

  it "raises eligible variants within bounds and skips the rest with reasons" do
    eligible = cached_product(title: "Whiskey", price: "100.00", inventory: 4)
    above = cached_product(title: "Notebook", price: "8.00", inventory: 200)

    run = run!

    expect(run.status).to eq("completed")
    expect(run.stats["applied"]).to eq(1)
    expect(run.stats["skipped"]).to eq(1)

    new_price = BigDecimal(variant_of(eligible)[:price])
    expect(new_price).to be > BigDecimal("100.00")
    expect(new_price).to be <= BigDecimal("150.00")
    expect(variant_of(eligible)[:original_price]).to eq("100.00")

    # Routine deterministic exclusions are counted, not copied into an
    # unbounded per-run history table.
    expect(run.price_changes.find_by(shopify_variant_gid: "#{above.shopify_gid}/v")).to be_nil

    applied_row = run.price_changes.find_by(status: "applied")
    expect(applied_row.action).to eq("increase")
    expect(applied_row.old_price).to eq(BigDecimal("100.00"))
  end

  it "is idempotent on an immediate second run (re-adjustment guard)" do
    cached_product(title: "Whiskey", price: "100.00", inventory: 4)
    run!
    second = run!
    expect(second.stats["applied"]).to eq(0)
    expect(second.stats["eligible"]).to eq(0)
  end

  it "does not lower the price after restock because above-threshold variants are not processed" do
    product = cached_product(title: "Whiskey", price: "100.00", inventory: 4)
    run! # raises it
    raised = BigDecimal(variant_of(product)[:price])
    expect(raised).to be > BigDecimal("100.00")

    # Simulate a restock above the threshold.
    v = variant_of(product)
    product.update!(variants: [ v.merge("inventory_quantity" => 60) ])

    restock_run = run!

    expect(restock_run.stats["applied"]).to eq(0)
    expect(restock_run.stats["skipped"]).to eq(1)
    expect(BigDecimal(variant_of(product)[:price])).to eq(raised)
  end

  it "restores an app-owned increase to base after restock when explicitly enabled" do
    Setting.instance.update!(price_restoration_enabled: true)
    product = cached_product(title: "Whiskey", price: "100.00", inventory: 4)
    run!
    raised = BigDecimal(variant_of(product)[:price])
    expect(raised).to be > BigDecimal("100.00")

    variant = variant_of(product)
    product.update!(variants: [ variant.merge("inventory_quantity" => 60) ])

    restock_run = run!
    restored = restock_run.price_changes.find_by(action: "restore")

    expect(restock_run.stats["restorable"]).to eq(1)
    expect(restock_run.stats["applied"]).to eq(1)
    expect(restored).to have_attributes(
      status: "applied",
      source: "system",
      old_price: raised,
      new_price: BigDecimal("100.00")
    )
    expect(restored.ai_reason).to include("above threshold 10")
    expect(BigDecimal(variant_of(product)[:price])).to eq(BigDecimal("100.00"))
    expect(variant_of(product)[:original_price]).to be_nil
    expect(variant_of(product)[:last_adjusted_at]).to be_nil

    expect(run!.stats["applied"]).to eq(0)
  end

  describe "Gemini fallback ladder" do
    let(:failing_recommender) do
      Class.new(Pricing::Recommender::Base) do
        def source_label = "gemini"

        def recommend(eligible, _settings)
          eligible.map do |item|
            Value::Recommendation.failed(variant_gid: item.variant.gid, error: :gemini_unavailable, source: "ai")
          end
        end
      end.new
    end

    def run_with(recommender)
      run = PricingRun.create!(status: "running", trigger: "manual", started_at: Time.current)
      Pricing::RunOrchestrator.new(client: Shopify::LocalClient.new, recommender: recommender).call(run)
      run.reload
    end

    it "skips unavailable variants when fallback is disabled" do
      Setting.instance.update!(fallback_pricing_enabled: false)
      cached_product(title: "Whiskey", price: "100.00", inventory: 4)

      run = run_with(failing_recommender)

      expect(run.stats["applied"]).to eq(0)
      row = run.price_changes.find_by(action: "increase")
      expect(row.status).to eq("skipped")
      expect(row.rejection_reason).to eq("gemini_unavailable")
    end

    it "prices with the deterministic formula when fallback is enabled" do
      Setting.instance.update!(fallback_pricing_enabled: true)
      product = cached_product(title: "Whiskey", price: "100.00", inventory: 4)

      run = run_with(failing_recommender)

      expect(run.stats["applied"]).to eq(1)
      expect(run.stats["fallback_used"]).to be(true)
      expect(run.stats["ai_unavailable"]).to be(true)
      row = run.price_changes.find_by(status: "applied")
      expect(row.source).to eq("fallback")
      expect(BigDecimal(variant_of(product)[:price])).to be > BigDecimal("100.00")
    end
  end

  it "leaves a merchant's manual price unchanged after restock" do
    Setting.instance.update!(price_restoration_enabled: true)
    # original 100, we wrote 130, but Shopify now shows 125 (merchant edit).
    product = cached_product(
      title: "Whiskey", price: "125.00", inventory: 60,
      original_price: "100.00", last_written_price: "130.00",
      last_adjusted_at: 1.day.ago.iso8601, inventory_at_last_adjustment: 4
    )
    run = run!
    expect(run.stats["applied"]).to eq(0)
    # Price is left as the merchant set it.
    expect(BigDecimal(variant_of(product)[:price])).to eq(BigDecimal("125.00"))
  end
end
