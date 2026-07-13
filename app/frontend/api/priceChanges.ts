import { useInfiniteQuery } from '@tanstack/react-query'
import { api } from '../lib/api'
import type { HistorySort, PriceChange, PriceChangeStatus } from '../lib/types'

interface Page {
  items: PriceChange[]
  next_cursor: number | null
}

export function priceChangesPath(
  status?: PriceChangeStatus,
  beforeId?: number | null,
  productId?: number | null,
  limit = 25,
  query?: string,
  sort: HistorySort = 'newest',
  variantGid?: string | null,
): string {
  const params = new URLSearchParams({ limit: String(limit) })
  if (beforeId) params.set('before_id', String(beforeId))
  if (status) params.set('status', status)
  if (productId) params.set('product_id', String(productId))
  if (query?.trim()) params.set('query', query.trim())
  if (sort !== 'newest') params.set('sort', sort)
  if (variantGid) params.set('variant_gid', variantGid)
  return `/api/v1/price_changes?${params.toString()}`
}

export function usePriceChanges(
  status?: PriceChangeStatus,
  productId?: number | null,
  query = '',
  sort: HistorySort = 'newest',
) {
  return useInfiniteQuery({
    queryKey: [
      'price_changes',
      status ?? 'all',
      productId ?? 'all-products',
      query,
      sort,
    ],
    initialPageParam: null as number | null,
    queryFn: ({ pageParam, signal }) =>
      api.get<Page>(
        priceChangesPath(status, pageParam, productId, 25, query, sort),
        { signal },
      ),
    getNextPageParam: (last) => last.next_cursor,
    staleTime: 15_000,
  })
}

export function useProductPriceChanges(
  productId: number | null,
  variantGid?: string | null,
) {
  return useInfiniteQuery({
    queryKey: ['price_changes', 'product-preview', productId, variantGid],
    initialPageParam: null as number | null,
    queryFn: ({ pageParam, signal }) =>
      api.get<Page>(
        priceChangesPath(
          undefined,
          pageParam,
          productId,
          10,
          undefined,
          'newest',
          variantGid,
        ),
        { signal },
      ),
    getNextPageParam: (last) => last.next_cursor,
    enabled: productId !== null,
    staleTime: 15_000,
  })
}
