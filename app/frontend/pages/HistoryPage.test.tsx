import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import HistoryPage from './HistoryPage'
import { renderWithProviders } from '../test/render'
import { server } from '../test/server'
import { priceChangesPath } from '../api/priceChanges'

const settings = {
  inventory_threshold: 5,
  max_price_percentage: '150.00',
  review_frequency: 'daily',
  ai_behavior_prompt: null,
  auto_pricing_enabled: true,
  fallback_pricing_enabled: true,
  price_restoration_enabled: false,
  next_run_at: null,
  currency: 'USD',
  ai_configured: true,
}

function change(overrides: Record<string, unknown> = {}) {
  return {
    id: 10,
    pricing_run_id: 2,
    product_title: 'Steel Bottle',
    variant_title: 'Large',
    shopify_variant_gid: 'gid://shopify/ProductVariant/10',
    status: 'rejected',
    action: 'increase',
    source: 'ai',
    old_price: '100.00',
    new_price: null,
    raw_recommended_price: '250.00',
    inventory_level: 2,
    ai_reason: null,
    rejection_reason: 'Recommendation exceeded the configured maximum.',
    created_at: '2026-07-12T08:00:00Z',
    ...overrides,
  }
}

describe('HistoryPage', () => {
  it('renders auditable recommendation outcomes', async () => {
    server.use(
      http.get('http://localhost:3000/api/v1/settings', () =>
        HttpResponse.json(settings),
      ),
      http.get('http://localhost:3000/api/v1/price_changes', ({ request }) => {
        const status = new URL(request.url).searchParams.get('status')
        return HttpResponse.json({
          items:
            status === 'failed'
              ? [
                  change({
                    id: 11,
                    product_title: 'Failed Product',
                    status: 'failed',
                    source: 'system',
                    rejection_reason: 'Shopify rejected the mutation.',
                    raw_recommended_price: null,
                  }),
                ]
              : [change()],
          next_cursor: null,
        })
      }),
    )
    renderWithProviders(<HistoryPage />)

    expect(await screen.findByText('Steel Bottle')).toBeInTheDocument()
    expect(screen.getByText('AI')).toBeInTheDocument()
    expect(
      screen.getByText(/Recommendation exceeded the configured maximum/),
    ).toBeInTheDocument()

    expect(priceChangesPath('failed', 42)).toBe(
      '/api/v1/price_changes?limit=25&before_id=42&status=failed',
    )
  })

  it('searches the complete history through the API and sorts chronologically', async () => {
    const requestedUrls: string[] = []
    server.use(
      http.get('http://localhost:3000/api/v1/settings', () =>
        HttpResponse.json(settings),
      ),
      http.get('http://localhost:3000/api/v1/price_changes', ({ request }) => {
        requestedUrls.push(request.url)
        const params = new URL(request.url).searchParams
        return HttpResponse.json({
          items: [
            change({
              product_title: params.get('query')
                ? 'Ceramic Mug'
                : 'Steel Bottle',
            }),
          ],
          next_cursor: null,
        })
      }),
    )
    const { user } = renderWithProviders(<HistoryPage />)

    await screen.findByText('Steel Bottle')
    await user.type(screen.getByLabelText('Search history'), 'ceramic')
    expect(await screen.findByText('Ceramic Mug')).toBeInTheDocument()
    await user.selectOptions(screen.getByLabelText('Sort by'), 'oldest')

    await waitFor(() =>
      expect(
        requestedUrls.some(
          (url) =>
            new URL(url).searchParams.get('query') === 'ceramic' &&
            new URL(url).searchParams.get('sort') === 'oldest',
        ),
      ).toBe(true),
    )
  })
})
