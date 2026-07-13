import {
  Badge,
  BlockStack,
  Box,
  Button,
  Card,
  InlineStack,
  Modal,
  Spinner,
  Text,
} from '@shopify/polaris'
import { useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { useProductPriceChanges } from '../api/priceChanges'
import {
  decisionReasonLabel,
  formatDateTime,
  formatMoney,
  formatRelative,
  sourceLabel,
} from '../lib/format'
import type { PriceChange, Product } from '../lib/types'

interface Props {
  product: Product | null
  variantGid: string | null
  currency: string
  onClose: () => void
}

export default function ProductHistoryModal({
  product,
  variantGid,
  currency,
  onClose,
}: Props) {
  const navigate = useNavigate()
  const variant = product?.variants.find((item) => item.gid === variantGid)
  const query = useProductPriceChanges(product?.id ?? null, variantGid)
  const rows = useMemo(
    () => query.data?.pages.flatMap((page) => page.items) ?? [],
    [query.data],
  )

  const viewFullHistory = () => {
    if (!product) return
    const params = new URLSearchParams({
      product_id: String(product.id),
      product: product.title,
    })
    onClose()
    navigate(`/history?${params.toString()}`)
  }

  return (
    <Modal
      open={product !== null}
      onClose={onClose}
      title={
        product
          ? `${product.title} · ${variant?.title || 'variant'} details`
          : 'Product details'
      }
      size="large"
      limitHeight
      primaryAction={{
        content: 'View product history',
        onAction: viewFullHistory,
        disabled: !product,
      }}
      secondaryActions={[{ content: 'Close', onAction: onClose }]}
    >
      <Modal.Section>
        {product && variant && (
          <BlockStack gap="400">
            <BlockStack gap="100">
              <Text as="h3" variant="headingMd">
                Pricing snapshot
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                Current Shopify state and the limits used for this variant.
              </Text>
            </BlockStack>
            <div className="price-detail-grid">
              <PriceDetail
                label="Current price"
                value={formatMoney(variant.price, currency)}
                help="Latest price synced from Shopify"
              />
              <PriceDetail
                label="Previous price"
                value={formatMoney(variant.previous_price, currency)}
                help={
                  variant.previous_price
                    ? 'Price immediately before the latest confirmed adjustment'
                    : 'No earlier automated price is recorded'
                }
              />
              <PriceDetail
                label="Base price"
                value={formatMoney(variant.base_price, currency)}
                help="Original merchant price before automated adjustments"
              />
              <PriceDetail
                label="Maximum price"
                value={formatMoney(variant.maximum_price, currency)}
                help="Computed from the global percentage and this base price"
              />
              <PriceDetail
                label="Inventory"
                value={
                  variant.tracked
                    ? String(variant.inventory_quantity ?? 0)
                    : 'Not tracked'
                }
                help={
                  variant.tracked
                    ? 'Tracked in Shopify'
                    : 'Inventory is not tracked'
                }
              />
            </div>

            <BlockStack gap="100">
              <Text as="h3" variant="headingMd">
                Decision history
              </Text>
              <Text as="p" tone="subdued" variant="bodySm">
                Newest first. Each event shows who made the decision, what
                happened, and why.
              </Text>
            </BlockStack>
          </BlockStack>
        )}

        {query.isLoading ? (
          <Box paddingBlock="600">
            <InlineStack align="center">
              <Spinner accessibilityLabel="Loading product history" />
            </InlineStack>
          </Box>
        ) : query.isError ? (
          <Card>
            <BlockStack gap="300">
              <Text as="p" tone="critical">
                {query.error instanceof Error
                  ? query.error.message
                  : 'Could not load this product’s history.'}
              </Text>
              <InlineStack>
                <Button onClick={() => query.refetch()}>Try again</Button>
              </InlineStack>
            </BlockStack>
          </Card>
        ) : rows.length === 0 ? (
          <Box paddingBlock="600">
            <BlockStack gap="200" inlineAlign="center">
              <Text as="h3" variant="headingMd">
                No pricing decisions yet
              </Text>
              <Text as="p" tone="subdued" alignment="center">
                This product’s recommendations, skips, and Shopify updates will
                appear here after a pricing run.
              </Text>
            </BlockStack>
          </Box>
        ) : (
          <BlockStack gap="300">
            {rows.map((row) => (
              <HistoryEvent key={row.id} row={row} currency={currency} />
            ))}
            {query.hasNextPage && (
              <InlineStack align="center">
                <Button
                  onClick={() => query.fetchNextPage()}
                  loading={query.isFetchingNextPage}
                >
                  Load 10 more
                </Button>
              </InlineStack>
            )}
          </BlockStack>
        )}
      </Modal.Section>
    </Modal>
  )
}

function PriceDetail({
  label,
  value,
  help,
}: {
  label: string
  value: string
  help: string
}) {
  return (
    <div className="price-detail-item">
      <BlockStack gap="100">
        <Text as="p" tone="subdued" variant="bodySm">
          {label}
        </Text>
        <Text as="p" variant="headingLg" numeric>
          {value}
        </Text>
        <Text as="p" tone="subdued" variant="bodySm">
          {help}
        </Text>
      </BlockStack>
    </div>
  )
}

function HistoryEvent({
  row,
  currency,
}: {
  row: PriceChange
  currency: string
}) {
  const reason = decisionReasonLabel(row.rejection_reason ?? row.ai_reason)
  const price = row.new_price
    ? `${formatMoney(row.old_price, currency)} → ${formatMoney(row.new_price, currency)}`
    : formatMoney(row.old_price, currency)
  const outcome = decisionTitle(row)

  return (
    <Card>
      <BlockStack gap="200">
        <InlineStack align="space-between" blockAlign="start" gap="300" wrap>
          <BlockStack gap="100">
            <InlineStack gap="200" blockAlign="center" wrap>
              <Text as="h3" variant="headingSm">
                {outcome}
              </Text>
              <Badge tone={row.source === 'ai' ? 'info' : undefined}>
                {sourceLabel(row.source)}
              </Badge>
            </InlineStack>
            <Text as="p" tone="subdued" variant="bodySm">
              {formatRelative(row.created_at)} ·{' '}
              {formatDateTime(row.created_at)}
            </Text>
          </BlockStack>
          <Text as="p" fontWeight="semibold" numeric>
            {price}
          </Text>
        </InlineStack>
        <Text as="p" tone="subdued">
          {reason}
        </Text>
      </BlockStack>
    </Card>
  )
}

function decisionTitle(row: PriceChange) {
  if (row.status === 'applied') {
    return row.action === 'restore' ? 'Price restored' : 'Price increased'
  }

  if (row.status === 'failed') return 'Price update failed'
  return `Recommendation ${row.status}`
}
