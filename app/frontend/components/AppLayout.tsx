import { ReactNode, useCallback } from 'react'
import { Frame, Navigation } from '@shopify/polaris'
import { HomeIcon, SettingsIcon, ClockIcon } from '@shopify/polaris-icons'
import { useLocation, useNavigate } from 'react-router-dom'

export default function AppLayout({ children }: { children: ReactNode }) {
  const location = useLocation()
  const navigate = useNavigate()

  const go = useCallback(
    (path: string) => (event?: React.MouseEvent<HTMLElement>) => {
      event?.preventDefault()
      navigate(path)
    },
    [navigate],
  )

  const navigationMarkup = (
    <Navigation location={location.pathname}>
      <Navigation.Section
        title="Dynamic Pricing"
        items={[
          {
            label: 'Dashboard',
            icon: HomeIcon,
            url: '/',
            selected: location.pathname === '/',
            onClick: go('/'),
          },
          {
            label: 'Price History',
            icon: ClockIcon,
            url: '/history',
            selected: location.pathname === '/history',
            onClick: go('/history'),
          },
          {
            label: 'Settings',
            icon: SettingsIcon,
            url: '/settings',
            selected: location.pathname === '/settings',
            onClick: go('/settings'),
          },
        ]}
      />
    </Navigation>
  )

  return <Frame navigation={navigationMarkup}>{children}</Frame>
}
