import { memo, useMemo, useState } from 'react'
import {
  Badge,
  BlockStack,
  Box,
  Button,
  Card,
  IndexTable,
  InlineGrid,
  InlineStack,
  Select,
  Text,
  TextField,
  Tooltip,
} from '@shopify/polaris'
import type {
  PriceChangeSource,
  PriceChangeStatus,
  Product,
} from '../lib/types'
import {
  decisionReasonLabel,
  formatDateTime,
  formatMoney,
  formatRelative,
  sourceLabel,
  statusTone,
} from '../lib/format'
import ProductHistoryModal from './ProductHistoryModal'

interface Row {
  id: string
  product: string
  variant: string
  vendor: string | null
  productType: string | null
  inventory: number | null
  tracked: boolean
  currentPrice: string
  basePrice: string
  eligibilityReason: string
  latestOldPrice: string | null
  latestNewPrice: string | null
  latestRecommendedPrice: string | null
  latestReason: string | null
  lastChangeAt: string | null
  latestSource: PriceChangeSource | null
  latestStatus: PriceChangeStatus | null
  productRecord: Product
}

type DecisionFilter = 'all' | PriceChangeStatus | 'none'
type SourceFilter = 'all' | PriceChangeSource

const DECISION_OPTIONS = [
  { label: 'Any decision', value: 'all' },
  { label: 'Applied', value: 'applied' },
  { label: 'Rejected', value: 'rejected' },
  { label: 'Skipped', value: 'skipped' },
  { label: 'Failed', value: 'failed' },
  { label: 'No decision yet', value: 'none' },
]

const SOURCE_OPTIONS = [
  { label: 'Any source', value: 'all' },
  { label: 'AI', value: 'ai' },
  { label: 'Fallback formula', value: 'fallback' },
  { label: 'System restoration', value: 'system' },
]

const PAGE_SIZE_OPTIONS = [
  { label: '10 rows', value: '10' },
  { label: '25 rows', value: '25' },
  { label: '50 rows', value: '50' },
]

function flatten(products: Product[]): Row[] {
  return products.flatMap((product) =>
    product.variants.map((variant) => ({
      id: variant.gid,
      product: product.title,
      variant: variant.title,
      vendor: product.vendor,
      productType: product.product_type,
      inventory: variant.inventory_quantity,
      tracked: variant.tracked,
      currentPrice: variant.price,
      basePrice: variant.base_price,
      eligibilityReason: variant.eligibility_reason,
      latestOldPrice: variant.latest_old_price ?? null,
      latestNewPrice: variant.latest_new_price ?? null,
      latestRecommendedPrice: variant.latest_recommended_price ?? null,
      latestReason: variant.latest_reason ?? null,
      lastChangeAt: variant.last_change_at ?? variant.last_adjusted_at,
      latestSource: variant.latest_source ?? null,
      latestStatus: variant.latest_status ?? null,
      productRecord: product,
    })),
  )
}

interface Props {
  products: Product[]
  currency?: string
  hasMoreProducts?: boolean
  loadingMoreProducts?: boolean
  onLoadMoreProducts?: () => void
}

function ProductsTable({
  products,
  currency = 'USD',
  hasMoreProducts = false,
  loadingMoreProducts = false,
  onLoadMoreProducts,
}: Props) {
  const [search, setSearch] = useState('')
  const [decision, setDecision] = useState<DecisionFilter>('all')
  const [source, setSource] = useState<SourceFilter>('all')
  const [pageSize, setPageSize] = useState(10)
  const [page, setPage] = useState(1)
  const [detailSelection, setDetailSelection] = useState<{
    product: Product
    variantGid: string
  } | null>(null)

  const rows = useMemo(() => flatten(products), [products])
  const filteredRows = useMemo(() => {
    const query = search.trim().toLocaleLowerCase()
    return rows.filter((row) => {
      const matchesSearch =
        !query ||
        [row.product, row.variant, row.vendor, row.productType]
          .filter(Boolean)
          .some((value) => value?.toLocaleLowerCase().includes(query))
      const matchesDecision =
        decision === 'all' ||
        (decision === 'none'
          ? row.latestStatus === null
          : row.latestStatus === decision)

      const matchesSource = source === 'all' || row.latestSource === source

      return matchesSearch && matchesDecision && matchesSource
    })
  }, [decision, rows, search, source])

  const totalPages = Math.max(1, Math.ceil(filteredRows.length / pageSize))
  const currentPage = Math.min(page, totalPages)
  const firstIndex = (currentPage - 1) * pageSize
  const visibleRows = filteredRows.slice(firstIndex, firstIndex + pageSize)
  const firstVisible = filteredRows.length === 0 ? 0 : firstIndex + 1
  const lastVisible = Math.min(firstIndex + pageSize, filteredRows.length)

  const filtersActive = search !== '' || decision !== 'all' || source !== 'all'
  const clearFilters = () => {
    setSearch('')
    setDecision('all')
    setSource('all')
    setPage(1)
  }

  return (
    <BlockStack gap="300">
      <Card>
        <BlockStack gap="300">
          <InlineGrid columns={{ xs: 1, sm: 2, lg: 4 }} gap="300">
            <TextField
              label="Search catalog"
              value={search}
              onChange={(value) => {
                setSearch(value)
                setPage(1)
              }}
              autoComplete="off"
              placeholder="Product, variant, vendor, or type"
              clearButton
              onClearButtonClick={() => {
                setSearch('')
                setPage(1)
              }}
            />
            <Select
              label="Latest outcome"
              options={DECISION_OPTIONS}
              value={decision}
              onChange={(value) => {
                setDecision(value as DecisionFilter)
                setPage(1)
              }}
            />
            <Select
              label="Decision source"
              options={SOURCE_OPTIONS}
              value={source}
              onChange={(value) => {
                setSource(value as SourceFilter)
                setPage(1)
              }}
            />
            <Select
              label="Rows per page"
              options={PAGE_SIZE_OPTIONS}
              value={String(pageSize)}
              onChange={(value) => {
                setPageSize(Number(value))
                setPage(1)
              }}
            />
          </InlineGrid>
          <InlineStack align="space-between" blockAlign="center" gap="200">
            <Text as="p" tone="subdued" variant="bodySm">
              {filteredRows.length === 0
                ? `No matches among ${rows.length} loaded variants`
                : `Showing ${firstVisible}–${lastVisible} of ${filteredRows.length} matching variants`}
            </Text>
            {filtersActive && (
              <Button variant="plain" onClick={clearFilters}>
                Clear filters
              </Button>
            )}
          </InlineStack>
        </BlockStack>
      </Card>

      {filteredRows.length === 0 ? (
        <Card>
          <Box paddingBlock="600">
            <BlockStack gap="200" inlineAlign="center">
              <Text as="h3" variant="headingMd">
                No variants match these filters
              </Text>
              <Text as="p" tone="subdued" alignment="center">
                Try a broader search or clear the outcome and source filters.
              </Text>
              <Button onClick={clearFilters}>Clear filters</Button>
            </BlockStack>
          </Box>
        </Card>
      ) : (
        <Card padding="0">
          <div className="catalog-table-scroll">
            <IndexTable
              resourceName={{ singular: 'variant', plural: 'variants' }}
              itemCount={visibleRows.length}
              selectable={false}
              headings={[
                { title: 'Product and variant' },
                { title: 'Inventory' },
                { title: 'Base price' },
                { title: 'Current price' },
                { title: 'Latest change' },
                { title: 'Source' },
                { title: 'Outcome' },
                { title: 'Explanation' },
                { title: 'Activity' },
              ]}
              pagination={{
                hasPrevious: currentPage > 1,
                hasNext: currentPage < totalPages,
                onPrevious: () => setPage((value) => Math.max(1, value - 1)),
                onNext: () =>
                  setPage((value) => Math.min(totalPages, value + 1)),
                label: `Page ${currentPage} of ${totalPages}`,
              }}
            >
              {visibleRows.map((row, index) => (
                <IndexTable.Row id={row.id} key={row.id} position={index}>
                  <IndexTable.Cell>
                    <BlockStack gap="100">
                      <Text as="span" fontWeight="semibold">
                        {row.product}
                      </Text>
                      <Text as="span" tone="subdued" variant="bodySm">
                        {row.variant}
                        {row.vendor ? ` · ${row.vendor}` : ''}
                      </Text>
                    </BlockStack>
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    {row.tracked ? (
                      <Text as="span" numeric>
                        {row.inventory ?? 0}
                      </Text>
                    ) : (
                      <Text as="span" tone="subdued">
                        Not tracked
                      </Text>
                    )}
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <Text as="span" numeric>
                      {formatMoney(row.basePrice, currency)}
                    </Text>
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <Text as="span" numeric>
                      {formatMoney(row.currentPrice, currency)}
                    </Text>
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <LatestChangeCell row={row} currency={currency} />
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <SourceCell source={row.latestSource} />
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <OutcomeCell status={row.latestStatus} />
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <ReasonCell
                      reason={row.latestReason ?? row.eligibilityReason}
                    />
                  </IndexTable.Cell>
                  <IndexTable.Cell>
                    <BlockStack gap="100">
                      <LastChangeCell timestamp={row.lastChangeAt} />
                      <Button
                        variant="plain"
                        textAlign="left"
                        onClick={() =>
                          setDetailSelection({
                            product: row.productRecord,
                            variantGid: row.id,
                          })
                        }
                        accessibilityLabel={`View details for ${row.product} ${row.variant}`}
                      >
                        View details
                      </Button>
                    </BlockStack>
                  </IndexTable.Cell>
                </IndexTable.Row>
              ))}
            </IndexTable>
          </div>
        </Card>
      )}

      {hasMoreProducts && (
        <Card>
          <InlineStack align="space-between" blockAlign="center" gap="300" wrap>
            <BlockStack gap="100">
              <Text as="p" fontWeight="semibold">
                More catalog products are available
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                Load the next Shopify catalog page, then use the table controls
                to move through the additional variants.
              </Text>
            </BlockStack>
            <Button onClick={onLoadMoreProducts} loading={loadingMoreProducts}>
              Load more products
            </Button>
          </InlineStack>
        </Card>
      )}

      <ProductHistoryModal
        product={detailSelection?.product ?? null}
        variantGid={detailSelection?.variantGid ?? null}
        currency={currency}
        onClose={() => setDetailSelection(null)}
      />
    </BlockStack>
  )
}

export default memo(ProductsTable)

function LatestChangeCell({ row, currency }: { row: Row; currency: string }) {
  if (!row.latestStatus) {
    return (
      <Text as="span" tone="subdued">
        —
      </Text>
    )
  }

  if (
    row.latestStatus !== 'applied' ||
    !row.latestOldPrice ||
    !row.latestNewPrice
  ) {
    const proposal = row.latestRecommendedPrice
    return (
      <Tooltip
        content={
          proposal
            ? `Proposed ${formatMoney(proposal, currency)}; no price was applied`
            : 'No price was applied'
        }
      >
        <Text as="span" tone="subdued" variant="bodySm">
          No price change
        </Text>
      </Tooltip>
    )
  }

  const oldPrice = Number(row.latestOldPrice)
  const newPrice = Number(row.latestNewPrice)
  const delta = newPrice - oldPrice
  if (!Number.isFinite(delta) || delta === 0) {
    return (
      <Text as="span" tone="subdued" variant="bodySm">
        No price change
      </Text>
    )
  }

  const increased = delta > 0
  return (
    <Tooltip
      content={`${formatMoney(row.latestOldPrice, currency)} to ${formatMoney(row.latestNewPrice, currency)}`}
    >
      <Text as="span" numeric fontWeight="semibold">
        {increased ? '+' : '−'} {formatMoney(String(Math.abs(delta)), currency)}
      </Text>
    </Tooltip>
  )
}

function SourceCell({ source }: { source: PriceChangeSource | null }) {
  return (
    <Text as="span" tone={source ? undefined : 'subdued'} variant="bodySm">
      {source ? sourceLabel(source) : '—'}
    </Text>
  )
}

function OutcomeCell({ status }: { status: PriceChangeStatus | null }) {
  if (!status) {
    return (
      <Text as="span" tone="subdued">
        —
      </Text>
    )
  }

  return (
    <Badge tone={statusTone(status)}>
      {status[0].toUpperCase() + status.slice(1)}
    </Badge>
  )
}

function ReasonCell({ reason }: { reason: string | null }) {
  const friendly = decisionReasonLabel(reason)
  const shortened =
    friendly.length > 88 ? `${friendly.slice(0, 88)}…` : friendly
  return (
    <Tooltip content={friendly} preferredPosition="above">
      <Text as="span" tone="subdued" variant="bodySm">
        {shortened}
      </Text>
    </Tooltip>
  )
}

function LastChangeCell({ timestamp }: { timestamp: string | null }) {
  if (!timestamp) {
    return (
      <Text as="span" tone="subdued" variant="bodySm">
        No activity yet
      </Text>
    )
  }

  return (
    <Tooltip content={formatDateTime(timestamp)}>
      <Text as="span" tone="subdued" variant="bodySm">
        {formatRelative(timestamp)}
      </Text>
    </Tooltip>
  )
}
