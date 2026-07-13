import { lazy, Suspense } from 'react'
import { AppProvider, Spinner } from '@shopify/polaris'
import enTranslations from '@shopify/polaris/locales/en.json'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import AppLayout from './components/AppLayout'

const DashboardPage = lazy(() => import('./pages/DashboardPage'))
const SettingsPage = lazy(() => import('./pages/SettingsPage'))
const HistoryPage = lazy(() => import('./pages/HistoryPage'))

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: false },
  },
})

export default function App() {
  return (
    <AppProvider i18n={enTranslations}>
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          <AppLayout>
            <Suspense fallback={<Spinner accessibilityLabel="Loading page" />}>
              <Routes>
                <Route path="/" element={<DashboardPage />} />
                <Route path="/history" element={<HistoryPage />} />
                <Route path="/settings" element={<SettingsPage />} />
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </Suspense>
          </AppLayout>
        </BrowserRouter>
      </QueryClientProvider>
    </AppProvider>
  )
}
