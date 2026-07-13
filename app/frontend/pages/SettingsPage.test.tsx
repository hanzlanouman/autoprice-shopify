import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import SettingsPage from './SettingsPage'
import { validateSettingsInput } from '../lib/settingsValidation'
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
  ai_configured: true,
}

describe('settings validation', () => {
  it('rejects unsafe or malformed values before a request is sent', () => {
    expect(
      validateSettingsInput({
        threshold: '-1.5',
        maxPricePercentage: '99',
        prompt: '',
      }),
    ).toEqual({
      inventory_threshold: 'Enter a whole number of zero or more.',
      max_price_percentage: 'Enter a percentage from 100 to 1,000.',
    })
  })
})

describe('SettingsPage', () => {
  it('saves a valid form through the API and confirms success', async () => {
    let received: unknown
    server.use(
      http.get('http://localhost:3000/api/v1/settings', () =>
        HttpResponse.json(settings),
      ),
      http.patch(
        'http://localhost:3000/api/v1/settings',
        async ({ request }) => {
          received = await request.json()
          return HttpResponse.json({ ...settings, inventory_threshold: 7 })
        },
      ),
    )
    const { user } = renderWithProviders(<SettingsPage />)

    const threshold = await screen.findByLabelText('Inventory threshold')
    await user.clear(threshold)
    await user.type(threshold, '7')
    await user.click(
      screen.getByLabelText('Restore prices when inventory recovers'),
    )
    await user.click(screen.getByRole('button', { name: 'Save' }))

    expect(await screen.findByText('Settings saved')).toBeInTheDocument()
    expect(received).toEqual({
      settings: expect.objectContaining({
        inventory_threshold: 7,
        price_restoration_enabled: true,
      }),
    })
  })

  it('shows a client-side error instead of submitting an invalid maximum', async () => {
    let updates = 0
    server.use(
      http.get('http://localhost:3000/api/v1/settings', () =>
        HttpResponse.json(settings),
      ),
      http.patch('http://localhost:3000/api/v1/settings', () => {
        updates += 1
        return HttpResponse.json(settings)
      }),
    )
    const { user } = renderWithProviders(<SettingsPage />)

    const maximum = await screen.findByLabelText('Maximum automated price')
    await user.clear(maximum)
    await user.click(screen.getByRole('button', { name: 'Save' }))

    expect(
      await screen.findByText('Enter a percentage from 100 to 1,000.'),
    ).toBeInTheDocument()
    await waitFor(() => expect(updates).toBe(0))
  })
})
