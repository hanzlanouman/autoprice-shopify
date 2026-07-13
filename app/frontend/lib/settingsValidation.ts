export function validateSettingsInput({
  threshold,
  maxPricePercentage,
  prompt,
}: {
  threshold: string
  maxPricePercentage: string
  prompt: string
}): Record<string, string> {
  const errors: Record<string, string> = {}
  const thresholdNumber = Number(threshold)
  const maximumNumber = Number(maxPricePercentage)

  if (
    threshold.trim() === '' ||
    !Number.isInteger(thresholdNumber) ||
    thresholdNumber < 0
  ) {
    errors.inventory_threshold = 'Enter a whole number of zero or more.'
  }
  if (
    maxPricePercentage.trim() === '' ||
    !Number.isFinite(maximumNumber) ||
    maximumNumber < 100 ||
    maximumNumber > 1000
  ) {
    errors.max_price_percentage = 'Enter a percentage from 100 to 1,000.'
  }
  if (prompt.length > 500) {
    errors.ai_behavior_prompt = 'Use 500 characters or fewer.'
  }

  return errors
}
