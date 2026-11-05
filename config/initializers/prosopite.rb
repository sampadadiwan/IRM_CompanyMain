# frozen_string_literal: true

# Opt-in N+1 query detection for development and test: PROSOPITE=1.
#
# Complements Bullet rather than replacing it: Prosopite matches repeated SQL fingerprints, so it
# catches N+1s Bullet cannot see (custom finders, exists?/pluck/count inside loops), while Bullet
# stays the tool for *unused* eager loading (see the safelist in config/environments/test.rb).
#
# Prosopite tracks queries per thread, so each controller action is wrapped individually. A
# scenario-level Before/After hook (as for Bullet) would miss every request in JS scenarios,
# which Capybara serves from a separate server thread.
#
#   PROSOPITE=1 bin/rails s                       # dev: warnings in log/prosopite.log
#   PROSOPITE=1 TEST_ENV_NUMBER=<n> bundle exec cucumber features/...
#   PROSOPITE_MIN=5                               # only report 5+ repeats (default 2)
return unless defined?(Prosopite) && ENV["PROSOPITE"].present?

Prosopite.rails_logger     = true # also echo into the Rails log, next to the request
Prosopite.prosopite_logger = true # log/prosopite.log
Prosopite.min_n_queries    = ENV.fetch("PROSOPITE_MIN", 2).to_i

ActiveSupport.on_load(:action_controller) do
  around_action do |_controller, action|
    Prosopite.scan
    action.call
  ensure
    Prosopite.finish
  end
end
