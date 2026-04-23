if Rails.env.test?
  Chewy.settings = {
    prefix: "test#{ENV['TEST_ENV_NUMBER']}"
  }
end
