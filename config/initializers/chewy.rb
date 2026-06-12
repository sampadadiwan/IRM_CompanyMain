if Rails.env.test?
  Chewy.settings = {
    prefix: "test#{ENV.fetch('TEST_ENV_NUMBER', nil)}"
  }
  # Bypass ES indexing in tests — the middleware uses this strategy per request,
  # and it must match the global :bypass set in features/support/env.rb.
  # Using :atomic here caused the middleware to override the outer :bypass and
  # trigger synchronous ES calls, which created missing indices (30s delay).
  Chewy.request_strategy = :bypass
end
