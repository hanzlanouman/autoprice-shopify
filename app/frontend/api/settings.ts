import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import type { Settings } from '../lib/types'

export function useSettings() {
  return useQuery({
    queryKey: ['settings'],
    queryFn: ({ signal }) => api.get<Settings>('/api/v1/settings', { signal }),
    staleTime: 60_000,
  })
}

export type SettingsInput = Partial<
  Pick<
    Settings,
    | 'inventory_threshold'
    | 'max_price_percentage'
    | 'review_frequency'
    | 'ai_behavior_prompt'
    | 'auto_pricing_enabled'
    | 'fallback_pricing_enabled'
    | 'price_restoration_enabled'
  >
>

export function useUpdateSettings() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: SettingsInput) =>
      api.patch<Settings>('/api/v1/settings', { settings: input }),
    onSuccess: (data) => {
      queryClient.setQueryData(['settings'], data)
      queryClient.invalidateQueries({ queryKey: ['products'] })
    },
  })
}
