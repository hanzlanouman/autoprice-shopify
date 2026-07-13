// Shared presenters used across pages so formatting lives in one place.
import type {
  PriceChangeStatus,
  PriceChangeAction,
  PricingProvider,
} from './types'

export function formatMoney(amount: string | null, currency = 'USD'): string {
  if (amount === null || amount === '') return '—'
  const value = Number(amount)
  if (Number.isNaN(value)) return amount
  try {
    return new Intl.NumberFormat(undefined, {
      style: 'currency',
      currency,
    }).format(value)
  } catch {
    return `${value.toFixed(2)}`
  }
}

export function formatDateTime(iso: string | null): string {
  if (!iso) return '—'
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return iso
  return date.toLocaleString()
}

export function formatRelative(iso: string | null): string {
  if (!iso) return 'never'
  const date = new Date(iso)
  const diffMs = date.getTime() - Date.now()
  const diffMin = Math.round(diffMs / 60000)
  const abs = Math.abs(diffMin)
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' })
  if (abs < 60) return rtf.format(diffMin, 'minute')
  const diffHr = Math.round(diffMin / 60)
  if (Math.abs(diffHr) < 24) return rtf.format(diffHr, 'hour')
  return rtf.format(Math.round(diffHr / 24), 'day')
}

export function priceDeltaPercent(
  oldPrice: string | null,
  newPrice: string | null,
): string {
  if (!oldPrice || !newPrice) return ''
  const from = Number(oldPrice)
  const to = Number(newPrice)
  if (!from || Number.isNaN(from) || Number.isNaN(to)) return ''
  const pct = ((to - from) / from) * 100
  const sign = pct > 0 ? '+' : ''
  return `${sign}${pct.toFixed(1)}%`
}

type BadgeTone = 'success' | 'critical' | 'warning' | 'info' | undefined

export function statusTone(status: PriceChangeStatus): BadgeTone {
  switch (status) {
    case 'applied':
      return 'success'
    case 'rejected':
    case 'failed':
      return 'critical'
    case 'skipped':
      return undefined
    default:
      return undefined
  }
}

export function sourceLabel(
  source: PricingProvider | string | null | undefined,
): string {
  switch (source) {
    case 'ai':
    case 'gemini':
      return 'AI'
    case 'fallback':
      return 'Fallback formula'
    case 'system':
      return 'System restoration'
    default:
      return 'Unknown'
  }
}

export function actionLabel(action: PriceChangeAction): string {
  return action === 'restore' ? 'Restore' : 'Increase'
}

const ELIGIBILITY_LABELS: Record<string, string> = {
  eligible: 'Eligible for repricing',
  gift_card: 'Gift cards are excluded from automatic pricing',
  untracked: 'Shopify is not tracking inventory for this variant',
  out_of_stock: 'Out of stock — pricing is paused',
  above_threshold: 'Stock is above your repricing threshold',
  at_ceiling: 'The price is already at its computed base-price maximum',
  already_adjusted:
    'Already adjusted — waiting for stock to fall further before another increase',
  not_evaluated: 'Eligibility has not been evaluated',
}

const DECISION_REASON_LABELS: Record<string, string> = {
  auto_pricing_disabled:
    'Automatic pricing is off, so this scheduled recommendation was not applied.',
  below_current:
    'The recommendation was below the current price and was rejected by the safety rules.',
  exceeds_max:
    'The recommendation exceeded this variant’s computed base-price maximum and was rejected by the safety rules.',
  invalid_precision:
    'The recommendation used unsupported price precision and was rejected.',
  malformed_response:
    'The AI response could not be safely understood, so no price was changed.',
  gemini_unavailable:
    'Gemini was unavailable, so this variant was safely skipped.',
  no_recommendation:
    'No trustworthy recommendation was returned for this variant.',
  no_change_recommended:
    'The recommended price matched the current price, so no change was needed.',
  confirmed_by_mutation_response:
    'Shopify confirmed that the price update was applied.',
  confirmed_from_live_price:
    'The live Shopify price confirmed that the earlier update succeeded.',
  shopify_write_not_applied:
    'Shopify kept the previous price, so the attempted update was recorded as failed.',
  live_price_changed_externally:
    'The live price was changed elsewhere, so this app did not overwrite it.',
}

export function eligibilityLabel(reason: string): string {
  return ELIGIBILITY_LABELS[reason] ?? reason.replaceAll('_', ' ')
}

/** Turns stored safety codes and deterministic messages into merchant-facing copy. */
export function decisionReasonLabel(reason: string | null | undefined): string {
  if (!reason?.trim()) return 'No explanation was recorded.'

  const value = reason.trim()
  const mapped = DECISION_REASON_LABELS[value] ?? ELIGIBILITY_LABELS[value]
  if (mapped) return mapped

  const scarcity = value.match(
    /^Inventory\s+(\d+)\s+of\s+threshold\s+(\d+)\s+[—-]\s+deterministic scarcity adjustment\.?$/i,
  )
  if (scarcity) {
    return `Only ${scarcity[1]} units remain (repricing threshold: ${scarcity[2]}). The fallback formula recommended this adjustment.`
  }

  const shopifyError = value.match(/^shopify_error:(.+)$/i)
  if (shopifyError) {
    return `Shopify rejected the price update: ${shopifyError[1].trim()}`
  }

  const uncertainWrite = value.match(/^shopify_outcome_unknown:(.+)$/i)
  if (uncertainWrite) {
    return `Shopify did not confirm the final price. The app will verify the live value before making another change. ${uncertainWrite[1].trim()}`
  }

  if (/^[a-z0-9_]+$/i.test(value)) {
    const sentence = value.replaceAll('_', ' ').toLocaleLowerCase()
    return `${sentence[0].toLocaleUpperCase()}${sentence.slice(1)}.`
  }

  return value
}
