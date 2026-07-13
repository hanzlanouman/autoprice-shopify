import { ReactNode } from 'react'
import { Banner, Card, SkeletonBodyText, BlockStack } from '@shopify/polaris'

// Shared loading/error/empty handling so every data view behaves consistently
// and no screen is ever blank (docs/ARCHITECTURE.md).
export function AsyncBoundary({
  isLoading,
  isError,
  error,
  isEmpty,
  emptyState,
  onRetry,
  children,
}: {
  isLoading: boolean
  isError: boolean
  error?: unknown
  isEmpty?: boolean
  emptyState?: ReactNode
  onRetry?: () => void
  children: ReactNode
}) {
  if (isLoading) {
    return (
      <Card>
        <BlockStack gap="300">
          <SkeletonBodyText lines={6} />
        </BlockStack>
      </Card>
    )
  }

  if (isError) {
    const message = error instanceof Error ? error.message : 'Please try again.'
    return (
      <Banner
        tone="critical"
        title="Something went wrong"
        action={
          onRetry ? { content: 'Try again', onAction: onRetry } : undefined
        }
      >
        {message}
      </Banner>
    )
  }

  if (isEmpty) {
    return <>{emptyState}</>
  }

  return <>{children}</>
}
