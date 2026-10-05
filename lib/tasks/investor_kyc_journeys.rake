# Seeds the investor KYC journey (one "Investor KYC" template and its catch-all auto-assignment rule)
# for every Investment Fund and Angel Fund entity, or one entity. Idempotent: anything already set up
# (including an admin's edits, or an entity's own KYC rules) is kept; existing KYCs get no journey.
#
#   bin/rails investor_kyc_journeys:rollout                 # dry run — prints what would be added
#   EXECUTE=1 bin/rails investor_kyc_journeys:rollout       # apply
#   ENTITY_ID=123 EXECUTE=1 bin/rails investor_kyc_journeys:rollout
#
# Run separately on IN and US.
# Worked examples H1 — openspec/changes/investor-kyc-journey/design.md#worked-examples
namespace :investor_kyc_journeys do
  desc "Seed the investor KYC journey for fund entities (dry run unless EXECUTE=1)"
  task rollout: :environment do
    JourneySetup.rollout("investor_kyc", execute: ENV["EXECUTE"] == "1", entity_id: ENV.fetch("ENTITY_ID", nil))
  end
end
