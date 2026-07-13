import { useEffect, useState, useCallback } from 'react'
import {
  Page,
  Layout,
  Card,
  FormLayout,
  TextField,
  Select,
  Checkbox,
  Banner,
  ContextualSaveBar,
  Toast,
  Text,
  BlockStack,
  InlineGrid,
} from '@shopify/polaris'
import {
  useSettings,
  useUpdateSettings,
  type SettingsInput,
} from '../api/settings'
import { AsyncBoundary } from '../components/AsyncBoundary'
import { ApiError } from '../lib/api'
import { formatRelative } from '../lib/format'
import { validateSettingsInput } from '../lib/settingsValidation'
import type { ReviewFrequency } from '../lib/types'

const FREQUENCY_OPTIONS = [
  { label: 'Every minute (demo/testing)', value: 'minute' },
  { label: 'Hourly', value: 'hourly' },
  { label: 'Daily', value: 'daily' },
  { label: 'Weekly', value: 'weekly' },
  { label: 'Monthly', value: 'monthly' },
]

function withoutError(errors: Record<string, string>, field: string) {
  const next = { ...errors }
  delete next[field]
  return next
}

function percentageInput(value: string) {
  const number = Number(value)
  return Number.isFinite(number) ? String(number) : value
}

export default function SettingsPage() {
  const { data: settings, isLoading, isError, error, refetch } = useSettings()

  return (
    <Page title="Settings" subtitle="Define how automatic pricing behaves">
      <Layout>
        <Layout.Section>
          <AsyncBoundary
            isLoading={isLoading}
            isError={isError}
            error={error}
            onRetry={() => refetch()}
          >
            {settings && (
              <SettingsForm initial={settings} currency={settings.currency} />
            )}
          </AsyncBoundary>
        </Layout.Section>
      </Layout>
    </Page>
  )
}

function SettingsForm({
  initial,
  currency,
}: {
  initial: import('../lib/types').Settings
  currency: string
}) {
  const update = useUpdateSettings()

  const [threshold, setThreshold] = useState(
    String(initial.inventory_threshold),
  )
  const [maxPricePercentage, setMaxPricePercentage] = useState(
    percentageInput(initial.max_price_percentage),
  )
  const [frequency, setFrequency] = useState<ReviewFrequency>(
    initial.review_frequency,
  )
  const [prompt, setPrompt] = useState(initial.ai_behavior_prompt ?? '')
  const [autoEnabled, setAutoEnabled] = useState(initial.auto_pricing_enabled)
  const [fallbackEnabled, setFallbackEnabled] = useState(
    initial.fallback_pricing_enabled,
  )
  const [restorationEnabled, setRestorationEnabled] = useState(
    initial.price_restoration_enabled,
  )
  const [toast, setToast] = useState(false)
  const [clientErrors, setClientErrors] = useState<Record<string, string>>({})

  const dirty =
    threshold !== String(initial.inventory_threshold) ||
    maxPricePercentage !== percentageInput(initial.max_price_percentage) ||
    frequency !== initial.review_frequency ||
    prompt !== (initial.ai_behavior_prompt ?? '') ||
    autoEnabled !== initial.auto_pricing_enabled ||
    fallbackEnabled !== initial.fallback_pricing_enabled ||
    restorationEnabled !== initial.price_restoration_enabled

  const serverFieldErrors: Record<string, string[]> =
    update.error instanceof ApiError ? (update.error.details ?? {}) : {}

  const fieldError = (field: string) =>
    clientErrors[field] ?? serverFieldErrors[field]?.join(', ')

  const reset = useCallback(() => {
    setThreshold(String(initial.inventory_threshold))
    setMaxPricePercentage(percentageInput(initial.max_price_percentage))
    setFrequency(initial.review_frequency)
    setPrompt(initial.ai_behavior_prompt ?? '')
    setAutoEnabled(initial.auto_pricing_enabled)
    setFallbackEnabled(initial.fallback_pricing_enabled)
    setRestorationEnabled(initial.price_restoration_enabled)
    setClientErrors({})
    update.reset()
  }, [initial, update])

  const save = useCallback(() => {
    const validationErrors = validateSettingsInput({
      threshold,
      maxPricePercentage,
      prompt,
    })
    setClientErrors(validationErrors)
    if (Object.keys(validationErrors).length > 0) return

    const input: SettingsInput = {
      inventory_threshold: Number(threshold),
      max_price_percentage: maxPricePercentage,
      review_frequency: frequency,
      ai_behavior_prompt: prompt,
      auto_pricing_enabled: autoEnabled,
      fallback_pricing_enabled: fallbackEnabled,
      price_restoration_enabled: restorationEnabled,
    }
    update.mutate(input, {
      onSuccess: () => {
        setClientErrors({})
        setToast(true)
      },
    })
  }, [
    threshold,
    maxPricePercentage,
    frequency,
    prompt,
    autoEnabled,
    fallbackEnabled,
    restorationEnabled,
    update,
  ])

  useEffect(() => {
    reset()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initial])

  return (
    <>
      {dirty && (
        <ContextualSaveBar
          message="Unsaved changes"
          saveAction={{
            onAction: save,
            loading: update.isPending,
            content: 'Save',
          }}
          discardAction={{ onAction: reset }}
        />
      )}
      {toast && (
        <Toast content="Settings saved" onDismiss={() => setToast(false)} />
      )}

      <BlockStack gap="400">
        {update.isError && (
          <Banner
            tone="critical"
            title="Settings were not saved"
            action={{ content: 'Try again', onAction: save }}
            onDismiss={() => update.reset()}
          >
            {update.error instanceof Error
              ? update.error.message
              : 'Review the highlighted values and try again.'}
          </Banner>
        )}

        <Banner tone="info" title="How pricing works">
          <p>
            When a variant’s stock falls to your threshold, it becomes eligible
            for an increase, never above its base-price cap. By default, stock
            above the threshold is not processed and prices are never lowered.
            You can explicitly opt into base-price restoration below. Merchant
            edits in Shopify always become the new base. Every change is logged.
          </p>
        </Banner>

        <Card>
          <BlockStack gap="400">
            <Checkbox
              label="Enable automatic pricing"
              checked={autoEnabled}
              onChange={setAutoEnabled}
              helpText="When on, prices update in your live store automatically — there is no approval step."
            />

            <FormLayout>
              <TextField
                label="Inventory threshold"
                type="number"
                min={0}
                suffix="units"
                value={threshold}
                onChange={(value) => {
                  setThreshold(value)
                  setClientErrors((errors) =>
                    withoutError(errors, 'inventory_threshold'),
                  )
                }}
                autoComplete="off"
                error={fieldError('inventory_threshold')}
                helpText="Products with this much stock or less become eligible for repricing."
              />
              <InlineGrid columns={{ xs: 1, md: 2 }} gap="400">
                <TextField
                  label="Maximum automated price"
                  type="number"
                  min={100}
                  max={1000}
                  suffix="%"
                  value={maxPricePercentage}
                  onChange={(value) => {
                    setMaxPricePercentage(value)
                    setClientErrors((errors) =>
                      withoutError(errors, 'max_price_percentage'),
                    )
                  }}
                  autoComplete="off"
                  error={fieldError('max_price_percentage')}
                  helpText={`Percentage of each product’s base price. 150% allows at most a 50% increase—for example, ${currency} 100 → ${currency} 150.`}
                />
                <Select
                  label="Pricing frequency"
                  options={FREQUENCY_OPTIONS}
                  value={frequency}
                  onChange={(v) => setFrequency(v as ReviewFrequency)}
                  helpText={
                    initial.next_run_at
                      ? `Next automatic review ${formatRelative(initial.next_run_at)}.`
                      : 'How often products are reviewed when automatic pricing is enabled.'
                  }
                />
              </InlineGrid>
              <TextField
                label="AI behavior prompt (optional)"
                multiline={3}
                value={prompt}
                onChange={(value) => {
                  setPrompt(value)
                  setClientErrors((errors) =>
                    withoutError(errors, 'ai_behavior_prompt'),
                  )
                }}
                autoComplete="off"
                maxLength={500}
                showCharacterCount
                placeholder="e.g. Be aggressive for premium products and conservative for low-cost items."
                error={fieldError('ai_behavior_prompt')}
                helpText="Style guidance for the AI. It cannot override your maximum price or thresholds."
              />
              <Checkbox
                label="Use fallback pricing when the AI is unavailable"
                checked={fallbackEnabled}
                onChange={setFallbackEnabled}
                helpText="If Gemini can’t be reached, use the same validated limits with a transparent, base-anchored scarcity formula. Such changes are labeled “Fallback”."
              />
              <Checkbox
                label="Restore prices when inventory recovers"
                checked={restorationEnabled}
                onChange={setRestorationEnabled}
                helpText="Optional and off by default. When stock rises above the threshold, restore only prices previously raised by this app to their stored base price. Merchant-edited prices are never overwritten."
              />
            </FormLayout>

            <Text as="p" tone="subdued" variant="bodySm">
              AI and fallback recommendations cannot decrease prices or exceed
              the computed cap. Only the separate restoration option can lower
              an app-owned price, and only back to its stored base. The
              one-minute cadence is intended only for short demo verification.
            </Text>
          </BlockStack>
        </Card>
      </BlockStack>
    </>
  )
}
