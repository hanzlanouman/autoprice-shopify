import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  Page,
  Card,
  IndexTable,
  Badge,
  Text,
  Button,
  Tabs,
  EmptyState,
  BlockStack,
  Tooltip,
  Banner,
  InlineGrid,
  InlineStack,
  Select,
  TextField,
} from '@shopify/polaris'
import { usePriceChanges } from '../api/priceChanges'
import { useSettings } from '../api/settings'
import { AsyncBoundary } from '../components/AsyncBoundary'
import {
  formatMoney,
  formatDateTime,
  priceDeltaPercent,
  statusTone,
  sourceLabel,
  actionLabel,
  decisionReasonLabel,
} from '../lib/format'
import type { HistorySort, PriceChange, PriceChangeStatus } from '../lib/types'

const TABS: Array<{ id: string; content: string; status?: PriceChangeStatus }> =
  [
    { id: 'all', content: 'All', status: undefined },
    { id: 'applied', content: 'Applied', status: 'applied' },
    { id: 'rejected', content: 'Rejected', status: 'rejected' },
    { id: 'skipped', content: 'Skipped', status: 'skipped' },
    { id: 'failed', content: 'Failed', status: 'failed' },
  ]

export default function HistoryPage() {
  const [tab, setTab] = useState(0)
  const [searchParams, setSearchParams] = useSearchParams()
  const status = TABS[tab].status
  const productIdValue = searchParams.get('product_id')
  const productId =
    productIdValue && /^\d+$/.test(productIdValue)
      ? Number(productIdValue)
      : null
  const productName = searchParams.get('product')
  const [search, setSearch] = useState('')
  const deferredSearch = useDebouncedValue(search, 300)
  const [sort, setSort] = useState<HistorySort>('newest')
  const { data: settings } = useSettings()
  const currency = settings?.currency ?? 'USD'

  const {
    data,
    isLoading,
    isError,
    error,
    refetch,
    fetchNextPage,
    hasNextPage,
    isFetchingNextPage,
    isFetchNextPageError,
  } = usePriceChanges(status, productId, deferredSearch, sort)

  const rows: PriceChange[] = useMemo(
    () => data?.pages.flatMap((p) => p.items) ?? [],
    [data],
  )

  return (
    <Page
      fullWidth
      title="Price History"
      subtitle="Search and audit every pricing recommendation and Shopify outcome"
    >
      <BlockStack gap="300">
        {productId && (
          <Banner
            tone="info"
            title={`Showing history for ${productName || 'one product'}`}
            action={{
              content: 'Show all products',
              onAction: () => setSearchParams({}),
            }}
          >
            Status tabs below apply only to this product until you clear the
            product filter.
          </Banner>
        )}
        <Card padding="0">
          <div className="history-controls">
            <BlockStack gap="300">
              <InlineGrid columns={{ xs: 1, sm: 2 }} gap="300">
                <TextField
                  label={
                    productId ? 'Search within this product' : 'Search history'
                  }
                  value={search}
                  onChange={setSearch}
                  autoComplete="off"
                  placeholder="Product, variant, vendor, type, or variant ID"
                  clearButton
                  onClearButtonClick={() => setSearch('')}
                />
                <Select
                  label="Sort by"
                  options={[
                    { label: 'Newest first', value: 'newest' },
                    { label: 'Oldest first', value: 'oldest' },
                  ]}
                  value={sort}
                  onChange={(value) => setSort(value as HistorySort)}
                />
              </InlineGrid>
              <InlineStack align="space-between" blockAlign="center" gap="200">
                <Text as="p" tone="subdued" variant="bodySm">
                  {search.trim()
                    ? `${rows.length} loaded ${rows.length === 1 ? 'result' : 'results'} matching “${search.trim()}”`
                    : `${rows.length} ${rows.length === 1 ? 'decision' : 'decisions'} loaded`}
                </Text>
                {search && (
                  <Button variant="plain" onClick={() => setSearch('')}>
                    Clear search
                  </Button>
                )}
              </InlineStack>
            </BlockStack>
          </div>
          <Tabs tabs={TABS} selected={tab} onSelect={setTab} />
          <AsyncBoundary
            isLoading={isLoading}
            isError={isError}
            error={error}
            onRetry={() => refetch()}
            isEmpty={rows.length === 0}
            emptyState={
              <EmptyState
                heading={
                  deferredSearch
                    ? 'No history matches this search'
                    : 'No price changes yet'
                }
                image=""
              >
                <p>
                  {deferredSearch
                    ? 'Try a product name, variant, vendor, or a broader term.'
                    : 'Applied changes, rejected recommendations, write failures, and restoration outcomes will appear here.'}
                </p>
              </EmptyState>
            }
          >
            <BlockStack gap="300">
              <IndexTable
                resourceName={{ singular: 'change', plural: 'changes' }}
                itemCount={rows.length}
                selectable={false}
                headings={[
                  { title: 'When' },
                  { title: 'Product' },
                  { title: 'Price decision' },
                  { title: 'Inventory' },
                  { title: 'Status' },
                  { title: 'Type' },
                  { title: 'Source' },
                  { title: 'Reason' },
                ]}
              >
                {rows.map((row, index) => (
                  <IndexTable.Row
                    id={String(row.id)}
                    key={row.id}
                    position={index}
                  >
                    <IndexTable.Cell>
                      <Text as="span" tone="subdued" variant="bodySm">
                        {formatDateTime(row.created_at)}
                      </Text>
                    </IndexTable.Cell>
                    <IndexTable.Cell>
                      <Text as="span" fontWeight="semibold">
                        {row.product_title ?? '—'}
                      </Text>
                      {row.variant_title && (
                        <Text as="span" tone="subdued">
                          {' '}
                          · {row.variant_title}
                        </Text>
                      )}
                    </IndexTable.Cell>
                    <IndexTable.Cell>
                      <PriceCell row={row} currency={currency} />
                    </IndexTable.Cell>
                    <IndexTable.Cell>
                      <Text as="span" numeric>
                        {row.inventory_level ?? '—'}
                      </Text>
                    </IndexTable.Cell>
                    <IndexTable.Cell>
                      <Badge tone={statusTone(row.status)}>
                        {row.status[0].toUpperCase() + row.status.slice(1)}
                      </Badge>
                    </IndexTable.Cell>
                    <IndexTable.Cell>
                      <Badge
                        tone={row.action === 'restore' ? 'info' : undefined}
                      >
                        {actionLabel(row.action)}
                      </Badge>
                    </IndexTable.Cell>
                    <IndexTable.Cell>{sourceLabel(row.source)}</IndexTable.Cell>
                    <IndexTable.Cell>
                      <ReasonCell row={row} />
                    </IndexTable.Cell>
                  </IndexTable.Row>
                ))}
              </IndexTable>

              {isFetchNextPageError && (
                <div style={{ padding: '12px' }}>
                  <Banner
                    tone="warning"
                    title="Couldn’t load more history"
                    action={{
                      content: 'Try again',
                      onAction: () => fetchNextPage(),
                    }}
                  />
                </div>
              )}

              {hasNextPage && (
                <div style={{ padding: '12px', textAlign: 'center' }}>
                  <Button
                    onClick={() => fetchNextPage()}
                    loading={isFetchingNextPage}
                  >
                    Load more
                  </Button>
                </div>
              )}
            </BlockStack>
          </AsyncBoundary>
        </Card>
      </BlockStack>
    </Page>
  )
}

function PriceCell({ row, currency }: { row: PriceChange; currency: string }) {
  if (row.status !== 'applied' || !row.new_price) {
    const proposed = row.raw_recommended_price ?? row.new_price
    return (
      <BlockStack gap="100">
        <Text as="span" tone="subdued" numeric>
          Current {formatMoney(row.old_price, currency)}
        </Text>
        {proposed && (
          <Text as="span" tone="subdued" variant="bodySm" numeric>
            Proposed {formatMoney(proposed, currency)}
          </Text>
        )}
      </BlockStack>
    )
  }
  const delta = priceDeltaPercent(row.old_price, row.new_price)
  const up = Number(row.new_price) >= Number(row.old_price)
  return (
    <Text as="span" numeric>
      {formatMoney(row.old_price, currency)} →{' '}
      {formatMoney(row.new_price, currency)}{' '}
      <Text as="span" tone={up ? 'success' : 'subdued'} variant="bodySm">
        ({up ? '↑' : '↓'} {delta})
      </Text>
    </Text>
  )
}

function useDebouncedValue<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value)

  useEffect(() => {
    const timeout = window.setTimeout(() => setDebounced(value), delay)
    return () => window.clearTimeout(timeout)
  }, [delay, value])

  return debounced
}

function ReasonCell({ row }: { row: PriceChange }) {
  const reason = decisionReasonLabel(row.rejection_reason ?? row.ai_reason)
  const extra =
    row.status === 'rejected' && row.raw_recommended_price
      ? ` The proposed price was ${row.raw_recommended_price}.`
      : ''
  const full = reason + extra
  if (full.length <= 60) {
    return (
      <Text as="span" tone="subdued" variant="bodySm">
        {full || '—'}
      </Text>
    )
  }
  return (
    <Tooltip content={full}>
      <Text as="span" tone="subdued" variant="bodySm">
        {full.slice(0, 60)}…
      </Text>
    </Tooltip>
  )
}
