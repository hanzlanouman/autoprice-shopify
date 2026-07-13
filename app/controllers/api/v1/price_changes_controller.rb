module Api
  module V1
    class PriceChangesController < BaseController
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      # Cursor-paginated by id (stable even when a run's rows share a
      # created_at). Filterable by product, variant, status, and text search.
      def index
        direction = params[:sort] == "oldest" ? :asc : :desc
        scope = PriceChange.includes(:product).order(id: direction)
        scope = scope.where(product_id: params[:product_id]) if params[:product_id].present?
        scope = scope.where(shopify_variant_gid: params[:variant_gid]) if params[:variant_gid].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = apply_search(scope, params[:query])
        if params[:before_id].present?
          operator = direction == :asc ? ">" : "<"
          scope = scope.where("price_changes.id #{operator} ?", params[:before_id])
        end

        limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        records = scope.limit(limit + 1).to_a
        has_more = records.size > limit
        items = records.first(limit)

        render json: {
          items: items.map { |pc| PriceChangeSerializer.new(pc).as_json },
          next_cursor: has_more ? items.last.id : nil
        }
      end

      private

      def apply_search(scope, query)
        term = query.to_s.strip.first(100)
        return scope if term.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        scope.left_joins(:product).where(
          <<~SQL.squish,
            products.title ILIKE :query OR
            products.vendor ILIKE :query OR
            products.product_type ILIKE :query OR
            price_changes.variant_title ILIKE :query OR
            price_changes.shopify_variant_gid ILIKE :query
          SQL
          query: pattern
        )
      end
    end
  end
end
