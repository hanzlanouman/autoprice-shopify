import {
  useInfiniteQuery,
  useMutation,
  useQueryClient,
} from '@tanstack/react-query'
import { api } from '../lib/api'
import type { Product } from '../lib/types'

export interface ProductsPage {
  products: Product[]
  currency: string
  next_cursor?: number | null
  synced_at?: string | null
}

export function useProducts() {
  return useInfiniteQuery({
    queryKey: ['products'],
    initialPageParam: null as number | null,
    queryFn: ({ pageParam, signal }) => {
      const params = new URLSearchParams({ limit: '50' })
      if (pageParam !== null) params.set('after_id', String(pageParam))
      return api.get<ProductsPage>(`/api/v1/products?${params.toString()}`, {
        signal,
      })
    },
    getNextPageParam: (lastPage) => lastPage.next_cursor ?? undefined,
    staleTime: 30_000,
  })
}

export function useSyncProducts() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => api.post<{ synced: number }>('/api/v1/products/sync'),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['products'] }),
  })
}
