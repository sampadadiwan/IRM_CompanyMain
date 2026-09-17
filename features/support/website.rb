# Support for @website scenarios, which exercise the host-gated static
# website middleware (lib/middleware/website.rb) through the full stack.
#
# The middleware is opt-in via ENV["WEBSITE_HOSTS"] and deliberately unset in
# the test env — this hook enables it for tagged scenarios only, with .test
# hosts so there is no interaction with the suite's BASE_DOMAIN=localhost:<port>
# tenant logic. The middleware re-reads the variable per request, so no
# stack rebuild is needed.
Around('@website') do |_scenario, block|
  original = ENV['WEBSITE_HOSTS']
  ENV['WEBSITE_HOSTS'] = 'caphive.test,www.caphive.test'
  block.call
ensure
  ENV['WEBSITE_HOSTS'] = original
end
