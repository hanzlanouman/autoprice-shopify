module Api
  module V1
    class ProductsController < BaseController
      # Reads the local cache (fast; no Shopify call per page view). Eligibility
      # is computed against current settings via Pricing::Bounds.
      def index
        settings = Setting.instance
        limit = (params[:limit].presence || 50).to_i.clamp(1, 100)
        scope = Product.active.order(:id)
        scope = scope.where("id > ?", params[:after_id]) if params[:after_id].present?
        records = scope.limit(limit + 1).to_a
        has_more = records.length > limit
        products = records.first(limit)
        variant_gids = products.flat_map { |product| product.variant_snapshots.map { |variant| variant[:gid] } }
        latest_changes = latest_changes_by_variant(variant_gids)
        latest_applied_changes = latest_applied_changes_by_variant(variant_gids)

        render json: {
          products: products.map do |product|
            ProductSerializer.new(
              product,
              settings: settings,
              latest_changes: latest_changes,
              latest_applied_changes: latest_applied_changes
            ).as_json
          end,
          currency: ShopInfo.currency,
          synced_at: Product.active.maximum(:synced_at)&.iso8601,
          next_cursor: has_more ? products.last.id : nil
        }
      end

      # On-demand cache refresh from Shopify (no pricing). 503 with a helpful
      # message when Shopify isn't configured.
      def sync
        raise Pricing::RunInProgressError, "A pricing run is in progress; sync when it finishes" if PricingRun.running?

        count = Pricing::ExecutionLock.with_lock do
          Pricing::ProductFetcher.new(client: Shopify::Client.build).call.size
        end
        render json: { synced: count }
      end

      private

      def latest_changes_by_variant(variant_gids)
        return {} if variant_gids.empty?

        PriceChange
          .where(shopify_variant_gid: variant_gids)
          .select("DISTINCT ON (shopify_variant_gid) price_changes.*")
          .order(:shopify_variant_gid, id: :desc)
          .index_by(&:shopify_variant_gid)
      end

      def latest_applied_changes_by_variant(variant_gids)
        return {} if variant_gids.empty?

        PriceChange
          .where(shopify_variant_gid: variant_gids, status: "applied")
          .select("DISTINCT ON (shopify_variant_gid) price_changes.*")
          .order(:shopify_variant_gid, id: :desc)
          .index_by(&:shopify_variant_gid)
      end
    end
  end
end
