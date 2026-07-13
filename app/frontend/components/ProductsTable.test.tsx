import { screen } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import ProductsTable from './ProductsTable'
import { renderWithProviders } from '../test/render'
import type { Product } from '../lib/types'
import { server } from '../test/server'

const products: Product[] = [
  {
    id: 1,
    shopify_gid: 'gid://shopify/Product/1',
    title: 'Steel Bottle',
    product_type: 'Drinkware',
    vendor: 'Acme',
    status: 'active',
    synced_at: '2026-07-12T08:00:00Z',
    variants: [
      {
        gid: 'gid://shopify/ProductVariant/11',
        title: 'Large',
        price: '100.00',
        inventory_quantity: 2,
        tracked: true,
        eligible: true,
        eligibility_reason: 'eligible',
        original_price: '100.00',
        base_price: '100.00',
        maximum_price: '150.00',
        previous_price: '90.00',
        last_adjusted_at: '2026-07-12T08:05:00Z',
        latest_recommended_price: '115.00',
        latest_old_price: '100.00',
        latest_new_price: '115.00',
        latest_reason: 'Very low inventory supports a modest increase.',
        last_change_at: '2026-07-12T08:05:00Z',
        latest_source: 'ai',
        latest_status: 'applied',
      },
    ],
  },
  {
    id: 2,
    shopify_gid: 'gid://shopify/Product/2',
    title: 'Ceramic Mug',
    product_type: 'Drinkware',
    vendor: 'Northstar',
    status: 'active',
    synced_at: '2026-07-12T08:00:00Z',
    variants: [
      {
        gid: 'gid://shopify/ProductVariant/22',
        title: 'Default',
        price: '20.00',
        inventory_quantity: 20,
        tracked: true,
        eligible: false,
        eligibility_reason: 'above_threshold',
        original_price: null,
        base_price: '20.00',
        maximum_price: '30.00',
        previous_price: null,
        last_adjusted_at: null,
      },
    ],
  },
]

describe('ProductsTable', () => {
  it('shows the latest decision, reason, source, and outcome', () => {
    renderWithProviders(<ProductsTable products={products} currency="USD" />)

    expect(screen.getByText('Steel Bottle')).toBeInTheDocument()
    expect(screen.getAllByText('Base price').length).toBeGreaterThan(0)
    expect(screen.getByText(/\+.*\$15\.00/)).toBeInTheDocument()
    expect(screen.getAllByText('Applied')).not.toHaveLength(0)
    expect(screen.getAllByText('AI').length).toBeGreaterThan(0)
    expect(
      screen.getByText('Very low inventory supports a modest increase.'),
    ).toBeInTheDocument()
  })

  it('filters by source and searchable product metadata', async () => {
    const { user } = renderWithProviders(
      <ProductsTable products={products} currency="USD" />,
    )

    await user.selectOptions(screen.getByLabelText('Decision source'), 'ai')
    expect(screen.getByText('Steel Bottle')).toBeInTheDocument()
    expect(screen.queryByText('Ceramic Mug')).not.toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Decision source'), 'all')
    await user.selectOptions(screen.getByLabelText('Latest outcome'), 'none')
    expect(screen.queryByText('Steel Bottle')).not.toBeInTheDocument()
    expect(screen.getByText('Ceramic Mug')).toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Latest outcome'), 'all')
    await user.type(screen.getByLabelText('Search catalog'), 'acme')
    expect(screen.getByText('Steel Bottle')).toBeInTheDocument()
    expect(screen.queryByText('Ceramic Mug')).not.toBeInTheDocument()
  })

  it('paginates variants and lets the merchant choose the page size', async () => {
    const manyVariants: Product[] = [
      {
        ...products[0],
        variants: Array.from({ length: 12 }, (_, index) => ({
          ...products[0].variants[0],
          gid: `gid://shopify/ProductVariant/${index + 1}`,
          title: `Size ${index + 1}`,
        })),
      },
    ]
    const { user } = renderWithProviders(
      <ProductsTable products={manyVariants} currency="USD" />,
    )

    expect(screen.getByText(/^Size 1 ·/)).toBeInTheDocument()
    expect(screen.queryByText(/^Size 11 ·/)).not.toBeInTheDocument()
    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument()

    await user.click(screen.getByRole('button', { name: 'Next' }))
    expect(screen.getByText(/^Size 11 ·/)).toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Rows per page'), '25')
    expect(screen.getByText(/^Size 1 ·/)).toBeInTheDocument()
    expect(screen.getByText(/^Size 12 ·/)).toBeInTheDocument()
  })

  it('opens recent product history from the catalog row', async () => {
    server.use(
      http.get('http://localhost:3000/api/v1/price_changes', ({ request }) => {
        const params = new URL(request.url).searchParams
        expect(params.get('product_id')).toBe('1')
        return HttpResponse.json({
          items: [
            {
              id: 41,
              pricing_run_id: 9,
              product_title: 'Steel Bottle',
              variant_title: 'Large',
              shopify_variant_gid: 'gid://shopify/ProductVariant/11',
              status: 'rejected',
              action: 'increase',
              source: 'ai',
              old_price: '100.00',
              new_price: null,
              raw_recommended_price: '250.00',
              inventory_level: 2,
              ai_reason: null,
              rejection_reason: 'exceeds_max',
              created_at: '2026-07-12T08:05:00Z',
            },
          ],
          next_cursor: null,
        })
      }),
    )
    const { user } = renderWithProviders(
      <ProductsTable products={products} currency="USD" />,
    )

    await user.click(
      screen.getByRole('button', {
        name: 'View details for Steel Bottle Large',
      }),
    )

    expect(
      await screen.findByText('Steel Bottle · Large details'),
    ).toBeInTheDocument()
    expect(screen.getByText('Previous price')).toBeInTheDocument()
    expect(screen.getByText(/\$90\.00/)).toBeInTheDocument()
    expect(screen.getAllByText('Base price').length).toBeGreaterThan(0)
    expect(screen.getByText('Maximum price')).toBeInTheDocument()
    expect(screen.getByText('Decision history')).toBeInTheDocument()
    expect(
      screen.getByText(
        'The recommendation exceeded this variant’s computed base-price maximum and was rejected by the safety rules.',
      ),
    ).toBeInTheDocument()
  })
})
