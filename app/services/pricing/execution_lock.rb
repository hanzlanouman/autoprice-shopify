module Pricing
  # One store-wide lock shared by pricing runs and manual catalogue syncs. It
  # prevents a sync based on an older Shopify snapshot from overwriting freshly
  # committed pricing guard state.
  module ExecutionLock
    KEY = 490_517
    module_function

    def with_lock
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        acquired = ActiveModel::Type::Boolean.new.cast(
          connection.select_value("SELECT pg_try_advisory_lock(#{KEY})")
        )
        raise RunInProgressError, "Another pricing or catalogue operation is in progress" unless acquired

        begin
          yield
        ensure
          connection.execute("SELECT pg_advisory_unlock(#{KEY})")
        end
      end
    end
  end
end
