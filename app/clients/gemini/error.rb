module Gemini
  # Base for Gemini adapter errors. The client maps transport/API failures into
  # this so the recommender degrades gracefully rather than crashing the run
  # (docs/ARCHITECTURE.md).
  class Error < StandardError; end
end
