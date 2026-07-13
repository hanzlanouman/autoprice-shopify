import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  Badge,
  Banner,
  BlockStack,
  EmptyState,
  InlineStack,
  Layout,
  Modal,
  Page,
  Text,
} from '@shopify/polaris'
import { useQueryClient } from '@tanstack/react-query'
import { useProducts, useSyncProducts } from '../api/products'
import { useCreateRun, useRuns } from '../api/pricingRuns'
import { useSettings } from '../api/settings'
import { AsyncBoundary } from '../components/AsyncBoundary'
import ProductsTable from '../components/ProductsTable'
import RunSummary from '../components/RunSummary'
import { formatRelative } from '../lib/format'
import type { PricingRun } from '../lib/types'

const RUN_START_TIMEOUT_MS = 60_000

interface QueuedRun {
  afterId: number
  acceptedAt: number
  expectedId?: number
}

interface RunObservation {
  status: PricingRun['status']
  pendingReconciliation: number
}

function errorMessage(error: unknown, fallback: string): string | null {
  if (error instanceof Error) return error.message
  return error ? fallback : null
}

export default function DashboardPage() {
  const queryClient = useQueryClient()
  const [queuedRun, setQueuedRun] = useState<QueuedRun | null>(null)
  const [queueTimedOut, setQueueTimedOut] = useState(false)
  const [showAiPreflight, setShowAiPreflight] = useState(false)

  const productQuery = useProducts()
  const { fetchNextPage: fetchNextProductsPage } = productQuery
  const sync = useSyncProducts()
  const runsQuery = useRuns({ pollWhileQueued: queuedRun !== null })
  const settingsQuery = useSettings()
  const createRun = useCreateRun()

  const products = useMemo(
    () => productQuery.data?.pages.flatMap((page) => page.products) ?? [],
    [productQuery.data],
  )
  const currency =
    productQuery.data?.pages[0]?.currency ??
    settingsQuery.data?.currency ??
    'USD'
  const runs = runsQuery.data
  const latestRun = runs?.[0]
  const workerRunning = runs?.some((run) => run.status === 'running') ?? false
  const isRunning = workerRunning || queuedRun !== null

  const syncedAt = useMemo(() => {
    const responseTimestamp = productQuery.data?.pages[0]?.synced_at
    if (responseTimestamp) return responseTimestamp

    return products.reduce<string | null>((latest, product) => {
      if (!product.synced_at) return latest
      if (!latest) return product.synced_at
      return new Date(product.synced_at).getTime() > new Date(latest).getTime()
        ? product.synced_at
        : latest
    }, null)
  }, [productQuery.data, products])

  const refreshPricingViews = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['products'] })
    queryClient.invalidateQueries({ queryKey: ['price_changes'] })
  }, [queryClient])

  // A queued job may not create its run row immediately. Keep polling until a
  // newer run appears instead of mistaking the previous completed run for it.
  useEffect(() => {
    if (!queuedRun || !runs) return

    const newRun = queuedRun.expectedId
      ? runs.find((run) => run.id === queuedRun.expectedId)
      : runs.find((run) => run.id > queuedRun.afterId)
    if (!newRun) return

    setQueuedRun(null)
    setQueueTimedOut(false)
    if (newRun.status !== 'running') refreshPricingViews()
  }, [queuedRun, refreshPricingViews, runs])

  useEffect(() => {
    if (!queuedRun) return

    const elapsed = Date.now() - queuedRun.acceptedAt
    const timeout = window.setTimeout(
      () => {
        setQueueTimedOut(true)
        setQueuedRun((current) => {
          if (current?.acceptedAt !== queuedRun.acceptedAt) return current
          return null
        })
      },
      Math.max(0, RUN_START_TIMEOUT_MS - elapsed),
    )

    return () => window.clearTimeout(timeout)
  }, [queuedRun])

  // Refresh product recommendations and history on a genuine running ->
  // settled transition. The ref avoids repeated invalidations while polling.
  const previousRuns = useRef<Map<number, RunObservation>>(new Map())
  useEffect(() => {
    if (!runs) return

    for (const run of runs) {
      const previous = previousRuns.current.get(run.id)
      const pendingReconciliation = run.stats.pending_reconciliation ?? 0
      if (
        (previous?.status === 'running' && run.status !== 'running') ||
        (previous &&
          previous.pendingReconciliation > 0 &&
          pendingReconciliation === 0)
      ) {
        refreshPricingViews()
      }
      previousRuns.current.set(run.id, {
        status: run.status,
        pendingReconciliation,
      })
    }
  }, [refreshPricingViews, runs])

  const startRun = useCallback(() => {
    const afterId =
      runs?.reduce((highest, run) => Math.max(highest, run.id), 0) ?? 0
    setQueueTimedOut(false)
    setQueuedRun({ afterId, acceptedAt: Date.now() })
    createRun.mutate(undefined, {
      onSuccess: (response) => {
        const expectedId = response.pricing_run?.id ?? response.pricing_run_id
        if (!expectedId) return
        setQueuedRun((current) =>
          current ? { ...current, expectedId } : current,
        )
      },
      onError: () => setQueuedRun(null),
    })
  }, [createRun, runs])

  const checkForQueuedRun = useCallback(() => {
    const afterId =
      runs?.reduce((highest, run) => Math.max(highest, run.id), 0) ?? 0
    setQueueTimedOut(false)
    setQueuedRun({ afterId, acceptedAt: Date.now() })
    runsQuery.refetch()
  }, [runs, runsQuery])

  const requestRun = useCallback(() => {
    if (settingsQuery.data && !settingsQuery.data.ai_configured) {
      setShowAiPreflight(true)
      return
    }
    startRun()
  }, [settingsQuery.data, startRun])

  const confirmRunWithoutAi = useCallback(() => {
    setShowAiPreflight(false)
    startRun()
  }, [startRun])

  const syncError = errorMessage(sync.error, 'Product sync failed.')
  const runError = errorMessage(
    createRun.error,
    'Could not start the pricing run.',
  )
  const runStats = latestRun?.stats
  const recommendationSource =
    runStats?.recommendation_source ?? runStats?.source
  const fallbackUsed =
    runStats?.fallback_used === true || recommendationSource === 'fallback'
  const aiUnavailable = runStats?.ai_unavailable === true
  const loadMoreProducts = useCallback(
    () => fetchNextProductsPage(),
    [fetchNextProductsPage],
  )

  return (
    <>
      <Modal
        open={showAiPreflight}
        onClose={() => setShowAiPreflight(false)}
        title="Gemini is not configured"
        primaryAction={{
          content: settingsQuery.data?.fallback_pricing_enabled
            ? 'Run with fallback'
            : 'Run without recommendations',
          onAction: confirmRunWithoutAi,
        }}
        secondaryActions={[
          { content: 'Cancel', onAction: () => setShowAiPreflight(false) },
        ]}
      >
        <Modal.Section>
          <Text as="p">
            {settingsQuery.data?.fallback_pricing_enabled
              ? 'Gemini cannot provide recommendations because no API key is configured. This run will use the deterministic scarcity engine. Its decisions use the same threshold and price cap, and will be labeled Fallback in history.'
              : 'Gemini cannot provide recommendations because no API key is configured, and fallback pricing is off. You may continue to verify the pipeline, but eligible variants will be safely skipped and no prices will change.'}
          </Text>
        </Modal.Section>
      </Modal>
      <Page
        fullWidth
        title="Dashboard"
        subtitle="Monitor inventory and every automated pricing decision"
        primaryAction={{
          content: isRunning ? 'Run in progress…' : 'Run now',
          loading: createRun.isPending || isRunning,
          disabled: isRunning || runsQuery.isLoading,
          onAction: requestRun,
        }}
        secondaryActions={[
          {
            content: 'Sync products',
            loading: sync.isPending,
            disabled: isRunning,
            onAction: () => sync.mutate(),
          },
        ]}
      >
        <Layout>
          <Layout.Section variant="fullWidth">
            <BlockStack gap="400">
              <InlineStack gap="200" blockAlign="center" wrap>
                <Badge
                  tone={
                    settingsQuery.data?.auto_pricing_enabled
                      ? 'success'
                      : undefined
                  }
                >
                  {settingsQuery.data?.auto_pricing_enabled
                    ? 'Auto-pricing on'
                    : 'Auto-pricing off'}
                </Badge>
                {settingsQuery.data?.auto_pricing_enabled &&
                  settingsQuery.data.next_run_at && (
                    <Text as="span" tone="subdued" variant="bodySm">
                      Next run {formatRelative(settingsQuery.data.next_run_at)}
                    </Text>
                  )}
                <Text as="span" tone="subdued" variant="bodySm">
                  Catalog synced {formatRelative(syncedAt)}
                </Text>
              </InlineStack>

              {settingsQuery.isError && (
                <Banner
                  tone="warning"
                  title="Settings could not be loaded"
                  action={{
                    content: 'Try again',
                    onAction: () => settingsQuery.refetch(),
                  }}
                >
                  {errorMessage(
                    settingsQuery.error,
                    'Settings are temporarily unavailable.',
                  )}
                </Banner>
              )}
              {runsQuery.isError && (
                <Banner
                  tone="warning"
                  title="Run status could not be loaded"
                  action={{
                    content: 'Try again',
                    onAction: () => runsQuery.refetch(),
                  }}
                >
                  {errorMessage(
                    runsQuery.error,
                    'Run status is temporarily unavailable.',
                  )}
                </Banner>
              )}
              {queuedRun && !workerRunning && (
                <Banner tone="info" title="Pricing run queued">
                  The worker accepted the request. This page will update when
                  processing starts.
                </Banner>
              )}
              {queueTimedOut && (
                <Banner
                  tone="warning"
                  title="The queued run has not started"
                  action={{
                    content: 'Check again',
                    onAction: checkForQueuedRun,
                  }}
                >
                  Confirm that the background worker is running. The request
                  remains safe to check again.
                </Banner>
              )}
              {runError && (
                <Banner
                  tone="warning"
                  title="Couldn’t start a run"
                  action={{ content: 'Try again', onAction: startRun }}
                  onDismiss={() => createRun.reset()}
                >
                  {runError}
                </Banner>
              )}
              {syncError && (
                <Banner
                  tone="warning"
                  title="Couldn’t sync from Shopify"
                  action={{
                    content: 'Try again',
                    onAction: () => sync.mutate(),
                  }}
                  onDismiss={() => sync.reset()}
                >
                  {syncError}
                </Banner>
              )}
              {sync.isSuccess && (
                <Banner
                  tone="success"
                  title={`${sync.data.synced} ${sync.data.synced === 1 ? 'product' : 'products'} synced`}
                  onDismiss={() => sync.reset()}
                >
                  The local catalog cache now reflects the latest Shopify data.
                </Banner>
              )}
              {latestRun?.status === 'failed' && latestRun.error_message && (
                <Banner tone="critical" title="Last run failed">
                  {latestRun.error_message}
                </Banner>
              )}
              {(latestRun?.stats.pending_reconciliation ?? 0) > 0 && (
                <Banner
                  tone="warning"
                  title="A Shopify write is being reconciled"
                >
                  The final Shopify outcome was uncertain. The worker will
                  verify the live price before another adjustment is allowed.
                </Banner>
              )}
              {(fallbackUsed || aiUnavailable) && (
                <Banner
                  tone="warning"
                  title={
                    fallbackUsed
                      ? 'Fallback pricing was used for the last run'
                      : 'AI recommendations were unavailable for the last run'
                  }
                >
                  {fallbackUsed
                    ? 'Gemini was unavailable or not configured, so the deterministic fallback formula handled affected recommendations. Every fallback decision is labeled in history.'
                    : 'Affected variants were safely skipped because no trustworthy AI recommendation was available.'}
                </Banner>
              )}

              <RunSummary run={latestRun} />

              <AsyncBoundary
                isLoading={productQuery.isLoading}
                isError={productQuery.isError}
                error={productQuery.error}
                onRetry={() => productQuery.refetch()}
                isEmpty={products.length === 0}
                emptyState={
                  <EmptyState
                    heading="No products yet"
                    action={{
                      content: 'Sync products',
                      onAction: () => sync.mutate(),
                      loading: sync.isPending,
                    }}
                    image=""
                  >
                    <p>
                      Sync your Shopify catalog to start monitoring inventory
                      and prices.
                    </p>
                  </EmptyState>
                }
              >
                <ProductsTable
                  products={products}
                  currency={currency}
                  hasMoreProducts={productQuery.hasNextPage}
                  loadingMoreProducts={productQuery.isFetchingNextPage}
                  onLoadMoreProducts={loadMoreProducts}
                />
              </AsyncBoundary>
            </BlockStack>
          </Layout.Section>
        </Layout>
      </Page>
    </>
  )
}
