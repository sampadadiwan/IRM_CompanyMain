# Support for @website_leads scenarios.
#
# WebsiteLeadsController derives its CORS allowlist from ENV["WEBSITE_HOSTS"] —
# the same variable lib/middleware/website.rb reads — so a scenario about which
# origins are allowed has to set it. .env.test does not define it (there is no
# static site in the test environment), which is itself worth asserting against:
# with the variable unset the allowlist is empty and NO origin is echoed back.
#
# Restored after every scenario so nothing leaks into the rest of the suite.
Around('@website_leads') do |_scenario, block|
  original = ENV.fetch("WEBSITE_HOSTS", nil)
  block.call
ensure
  if original.nil?
    ENV.delete("WEBSITE_HOSTS")
  else
    ENV["WEBSITE_HOSTS"] = original
  end
end
