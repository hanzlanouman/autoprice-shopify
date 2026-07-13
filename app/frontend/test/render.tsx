import type { ReactElement } from 'react'
import { AppProvider, Frame } from '@shopify/polaris'
import enTranslations from '@shopify/polaris/locales/en.json'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'

export function renderWithProviders(ui: ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },
      mutations: { retry: false },
    },
  })

  return {
    user: userEvent.setup(),
    queryClient,
    ...render(
      <AppProvider i18n={enTranslations}>
        <QueryClientProvider client={queryClient}>
          <MemoryRouter>
            <Frame>{ui}</Frame>
          </MemoryRouter>
        </QueryClientProvider>
      </AppProvider>,
    ),
  }
}
