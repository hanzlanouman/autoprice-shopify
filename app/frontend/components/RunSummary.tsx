import {
  Card,
  InlineGrid,
  BlockStack,
  Text,
  Badge,
  InlineStack,
} from '@shopify/polaris'
import type { PricingRun } from '../lib/types'
import { formatRelative, sourceLabel } from '../lib/format'

function Stat({
  label,
  value,
  tone,
}: {
  label: string
  value: number
  tone?: 'success' | 'critical' | 'subdued'
}) {
  return (
    <Card>
      <BlockStack gap="100">
        <Text
          as="span"
          variant="headingLg"
          tone={tone === 'subdued' ? 'subdued' : undefined}
        >
          {value}
        </Text>
        <Text as="span" tone="subdued" variant="bodySm">
          {label}
        </Text>
      </BlockStack>
    </Card>
  )
}

export default function RunSummary({ run }: { run?: PricingRun }) {
  if (!run) {
    return (
      <Card>
        <Text as="p" tone="subdued">
          No pricing runs yet. Use “Run now” to generate recommendations.
        </Text>
      </Card>
    )
  }

  const s = run.stats
  const statusTone =
    run.status === 'completed'
      ? 'success'
      : run.status === 'failed'
        ? 'critical'
        : 'attention'
  const source = s.recommendation_source ?? s.source

  return (
    <BlockStack gap="300">
      <InlineStack gap="200" blockAlign="center">
        <Badge tone={statusTone}>{`Last run: ${run.status}`}</Badge>
        <Text as="span" tone="subdued" variant="bodySm">
          {formatRelative(run.finished_at ?? run.started_at)}
          {source ? ` · recommendations by ${sourceLabel(source)}` : ''}
        </Text>
      </InlineStack>

      <InlineGrid columns={{ xs: 2, sm: 3, md: 6 }} gap="300">
        <Stat label="Eligible" value={s.eligible ?? 0} />
        <Stat label="Applied" value={s.applied ?? 0} tone="success" />
        <Stat
          label="Rejected"
          value={s.rejected ?? 0}
          tone={s.rejected ? 'critical' : 'subdued'}
        />
        <Stat label="Skipped" value={s.skipped ?? 0} tone="subdued" />
        <Stat
          label="Failed"
          value={s.failed ?? 0}
          tone={s.failed ? 'critical' : 'subdued'}
        />
        <Stat
          label="Pending reconciliation"
          value={s.pending_reconciliation ?? 0}
          tone={s.pending_reconciliation ? 'critical' : 'subdued'}
        />
      </InlineGrid>
    </BlockStack>
  )
}
