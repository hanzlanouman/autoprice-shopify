import { screen } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import DashboardPage from './DashboardPage'
import { renderWithProviders } from '../test/render'
import { server } from '../test/server'

const settings = {
  inventory_threshold: 5,
  max_price_percentage: '150.00',
  review_frequency: 'daily',
  ai_behavior_prompt: null,
  auto_pricing_enabled: true,
  fallback_pricing_enabled: true,
  price_restoration_enabled: false,
  next_run_at: '2026-07-13T08:00:00Z',
  currency: 'USD',
  ai_configured: false,
}

function product(id: number, title: string) {
  return {
    id,
    shopify_gid: `gid://shopify/Product/${id}`,
    title,
    product_type: 'Accessories',
    vendor: 'Demo Vendor',
    status: 'active',
    synced_at: '2026-07-12T08:00:00Z',
    variants: [
      {
        gid: `gid://shopify/ProductVariant/${id}`,
        title: 'Default',
        price: '50.00',
        inventory_quantity: 3,
        tracked: true,
        eligible: true,
        eligibility_reason: 'eligible',
        original_price: '50.00',
        base_price: '50.00',
        maximum_price: '75.00',
        previous_price: '50.00',
        last_adjusted_at: null,
        latest_recommended_price: '55.00',
        latest_old_price: '50.00',
        latest_new_price: '55.00',
        latest_reason: 'Inventory is scarce.',
        last_change_at: '2026-07-12T08:05:00Z',
        latest_source: 'fallback',
        latest_status: 'applied',
      },
    ],
  }
}

function useDashboardHandlers() {
  server.use(
    http.get('http://localhost:3000/api/v1/settings', () =>
      HttpResponse.json(settings),
    ),
    http.get('http://localhost:3000/api/v1/pricing_runs', () =>
      HttpResponse.json({
        pricing_runs: [
          {
            id: 9,
            status: 'completed',
            trigger: 'scheduled',
            started_at: '2026-07-12T08:00:00Z',
            finished_at: '2026-07-12T08:05:00Z',
            stats: {
              eligible: 1,
              applied: 1,
              recommendation_source: 'fallback',
              fallback_used: true,
              ai_unavailable: true,
            },
            error_message: null,
          },
        ],
      }),
    ),
    http.get('http://localhost:3000/api/v1/products', ({ request }) => {
      const cursor = new URL(request.url).searchParams.get('after_id')
      return cursor
        ? HttpResponse.json({
            products: [product(2, 'Second Product')],
            currency: 'USD',
            next_cursor: null,
            synced_at: '2026-07-12T08:00:00Z',
          })
        : HttpResponse.json({
            products: [product(1, 'First Product')],
            currency: 'USD',
            next_cursor: 1,
            synced_at: '2026-07-12T08:00:00Z',
          })
    }),
  )
}

describe('DashboardPage', () => {
  it('shows fallback health, sync state, enriched products, and pagination', async () => {
    useDashboardHandlers()
    const { user } = renderWithProviders(<DashboardPage />)

    expect(await screen.findByText('First Product')).toBeInTheDocument()
    expect(screen.getByText(/Catalog synced/)).toBeInTheDocument()
    expect(
      screen.getByText('Fallback pricing was used for the last run'),
    ).toBeInTheDocument()
    expect(screen.getByText('Inventory is scarce.')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Load more products' }))
    expect(await screen.findByText('Second Product')).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Load more products' }),
    ).not.toBeInTheDocument()
  })

  it('offers a working retry when product loading fails', async () => {
    let attempts = 0
    useDashboardHandlers()
    server.use(
      http.get('http://localhost:3000/api/v1/products', () => {
        attempts += 1
        if (attempts === 1) {
          return HttpResponse.json(
            {
              error: {
                code: 'temporary',
                message: 'Temporary Shopify failure.',
              },
            },
            { status: 503 },
          )
        }
        return HttpResponse.json({
          products: [product(1, 'Recovered Product')],
          currency: 'USD',
        })
      }),
    )
    const { user } = renderWithProviders(<DashboardPage />)

    expect(
      await screen.findByText('Temporary Shopify failure.'),
    ).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByText('Recovered Product')).toBeInTheDocument()
  })

  it('asks before a manual run uses fallback without Gemini', async () => {
    let requested = false
    useDashboardHandlers()
    server.use(
      http.post('http://localhost:3000/api/v1/pricing_runs', () => {
        requested = true
        return HttpResponse.json(
          {
            enqueued: true,
            pricing_run: {
              id: 10,
              status: 'running',
              trigger: 'manual',
              started_at: null,
              finished_at: null,
              stats: {},
              error_message: null,
            },
          },
          { status: 202 },
        )
      }),
    )
    const { user } = renderWithProviders(<DashboardPage />)

    await screen.findByText('First Product')
    await user.click(screen.getByRole('button', { name: 'Run now' }))

    expect(screen.getByText('Gemini is not configured')).toBeInTheDocument()
    expect(requested).toBe(false)
    await user.click(screen.getByRole('button', { name: 'Run with fallback' }))
    expect(requested).toBe(true)
  })
})
