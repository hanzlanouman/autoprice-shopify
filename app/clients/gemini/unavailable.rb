module Gemini
  # Raised on timeouts, 5xx, 429 after retries, auth failures, or an unusable
  # response body — anything that means "we got no usable answer".
  class Unavailable < Error; end
end
