# Rolls out the capital call journeys (openspec change capital-call-journey).
#
# Seeds, per fund entity, the two journey templates (Full / Light), the auto-assignment rules that
# launch them on NEW calls, and the workflow templates permission. It never launches a journey on
# an existing call: only calls created afterwards get one.
#
# Dry run by default (prints what it would do, writes nothing):
#   bin/rails capital_call_journeys:rollout
#   bin/rails capital_call_journeys:rollout ENTITY_ID=18
# Apply:
#   EXECUTE=1 bin/rails capital_call_journeys:rollout
#
# IN and US are independent: run it on each. The work is JourneySetup.rollout, shared with
# capital_distribution_journeys:rollout (capital-distribution-journey design Decision 6).
# Worked examples H1, H10, H11, E14, E15 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
namespace :capital_call_journeys do
  desc "Seed capital call journeys for fund entities (dry run unless EXECUTE=1)"
  task rollout: :environment do
    JourneySetup.rollout("capital_call", execute: ENV["EXECUTE"] == "1", entity_id: ENV.fetch("ENTITY_ID", nil))
  end
end
