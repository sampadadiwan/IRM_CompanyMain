# Rolls out the capital distribution journeys (openspec change capital-distribution-journey).
#
# Seeds, per fund entity, the two journey templates (Full / Light), the auto-assignment rules that
# launch them on NEW distributions, and the workflow templates permission. It never launches a
# journey on an existing distribution: only distributions created afterwards get one.
#
# Dry run by default (prints what it would do, writes nothing):
#   bin/rails capital_distribution_journeys:rollout
#   bin/rails capital_distribution_journeys:rollout ENTITY_ID=18
# Apply:
#   EXECUTE=1 bin/rails capital_distribution_journeys:rollout
#
# IN and US are independent: run it on each. The work is JourneySetup.rollout, shared with
# capital_call_journeys:rollout (design Decision 6).
# Worked examples H1, E20 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
namespace :capital_distribution_journeys do
  desc "Seed capital distribution journeys for fund entities (dry run unless EXECUTE=1)"
  task rollout: :environment do
    JourneySetup.rollout("capital_distribution", execute: ENV["EXECUTE"] == "1", entity_id: ENV.fetch("ENTITY_ID", nil))
  end
end
