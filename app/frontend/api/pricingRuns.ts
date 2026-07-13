import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { api } from '../lib/api'
import type { PricingRun } from '../lib/types'

export function useRuns({
  pollWhileQueued = false,
}: { pollWhileQueued?: boolean } = {}) {
  return useQuery({
    queryKey: ['pricing_runs'],
    queryFn: ({ signal }) =>
      api
        .get<{ pricing_runs: PricingRun[] }>('/api/v1/pricing_runs', { signal })
        .then((r) => r.pricing_runs),
    staleTime: 1_000,
    // Poll while a run is in progress; stop once everything settles.
    refetchInterval: (query) => {
      const runs = query.state.data as PricingRun[] | undefined
      const unsettled = runs?.some(
        (run) =>
          run.status === 'running' ||
          (run.stats.pending_reconciliation ?? 0) > 0,
      )
      return pollWhileQueued || unsettled ? 2000 : false
    },
  })
}

export interface CreatePricingRunResponse {
  enqueued: boolean
  pricing_run_id?: number
  pricing_run?: PricingRun
}

export function useCreateRun() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () =>
      api.post<CreatePricingRunResponse>('/api/v1/pricing_runs'),
    onSuccess: (response) => {
      const run = response.pricing_run
      if (run) {
        queryClient.setQueryData<PricingRun[]>(
          ['pricing_runs'],
          (current = []) => [
            run,
            ...current.filter((currentRun) => currentRun.id !== run.id),
          ],
        )
      }
      queryClient.invalidateQueries({ queryKey: ['pricing_runs'] })
    },
  })
}
