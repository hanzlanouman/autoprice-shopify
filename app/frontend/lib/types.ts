// TS mirror of the API serializers (docs/ARCHITECTURE.md). Money is transported as a
// string (e.g. "149.99") and only parsed for display via lib/format.

export type ReviewFrequency =
  'minute' | 'hourly' | 'daily' | 'weekly' | 'monthly'

export interface Settings {
  inventory_threshold: number
  max_price_percentage: string
  review_frequency: ReviewFrequency
  ai_behavior_prompt: string | null
  auto_pricing_enabled: boolean
  fallback_pricing_enabled: boolean
  price_restoration_enabled: boolean
  next_run_at: string | null
  currency: string
  ai_configured: boolean
}

export interface VariantSnapshot {
  gid: string
  title: string
  price: string
  inventory_quantity: number | null
  tracked: boolean
  eligible: boolean
  eligibility_reason: string
  original_price: string | null
  base_price: string
  maximum_price: string | null
  previous_price: string | null
  last_adjusted_at: string | null
  latest_recommended_price?: string | null
  latest_old_price?: string | null
  latest_new_price?: string | null
  latest_reason?: string | null
  last_change_at?: string | null
  latest_source?: PriceChangeSource | null
  latest_status?: PriceChangeStatus | null
}

export interface Product {
  id: number
  shopify_gid: string
  title: string
  product_type: string | null
  vendor: string | null
  status: string
  synced_at: string | null
  variants: VariantSnapshot[]
}

export type PriceChangeStatus = 'applied' | 'rejected' | 'failed' | 'skipped'
export type PriceChangeAction = 'increase' | 'restore'
export type PriceChangeSource = 'ai' | 'fallback' | 'system'
export type HistorySort = 'newest' | 'oldest'
export type PricingProvider = PriceChangeSource | 'gemini'

export interface PriceChange {
  id: number
  pricing_run_id: number
  product_title: string
  variant_title: string | null
  shopify_variant_gid: string
  status: PriceChangeStatus
  action: PriceChangeAction
  source: PriceChangeSource
  old_price: string | null
  new_price: string | null
  raw_recommended_price: string | null
  inventory_level: number | null
  ai_reason: string | null
  rejection_reason: string | null
  created_at: string
}

export interface PricingRunStats {
  products_fetched?: number
  eligible?: number
  restorable?: number
  applied?: number
  rejected?: number
  failed?: number
  skipped?: number
  pending_reconciliation?: number
  source?: PricingProvider
  recommendation_source?: PricingProvider
  fallback_used?: boolean
  ai_unavailable?: boolean
  gemini_calls?: number
  gemini_input_tokens?: number
  gemini_output_tokens?: number
}

export type PricingRunStatus = 'running' | 'completed' | 'failed'

export interface PricingRun {
  id: number
  status: PricingRunStatus
  trigger: 'scheduled' | 'manual'
  started_at: string | null
  finished_at: string | null
  stats: PricingRunStats
  error_message: string | null
  price_changes?: PriceChange[]
}

export interface Paginated<T> {
  items: T[]
  next_cursor: number | null
}
