if Rails.env.test?
  Chewy.settings = {
    prefix: "test#{ENV['TEST_ENV_NUMBER']}"
  }
  # Use atomic strategy in tests to ensure synchronous updates and isolation
  Chewy.request_strategy = :atomic
end
