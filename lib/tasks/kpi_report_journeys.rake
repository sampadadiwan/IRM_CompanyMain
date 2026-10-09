# Seeds the KPI report journey (one "KPI Report Review" template and its catch-all auto-assignment
# rule) for every Investment Fund that uses KPIs, or one entity. Idempotent: anything already set up
# (including an admin's edits, or an entity's own KPI report rules) is kept; existing reports get no
# journey — only reports requested afterwards do.
#
#   bin/rails kpi_report_journeys:rollout                 # dry run — prints what would be added
#   EXECUTE=1 bin/rails kpi_report_journeys:rollout       # apply
#   ENTITY_ID=123 EXECUTE=1 bin/rails kpi_report_journeys:rollout
#
# Run separately on IN and US.
# Worked examples H1, E4 — openspec/changes/kpi-report-journey/design.md#worked-examples
namespace :kpi_report_journeys do
  desc "Seed the KPI report journey for fund entities using KPIs (dry run unless EXECUTE=1)"
  task rollout: :environment do
    JourneySetup.rollout("kpi_report", execute: ENV["EXECUTE"] == "1", entity_id: ENV.fetch("ENTITY_ID", nil))
  end
end
