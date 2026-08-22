# frozen_string_literal: true

# Demo data for the Presentation Analyst Dashboard.
#
# Fabricates SupportAgentReport rows in the shape PresentationAnalystAgent#store_results
# writes, so the dashboard can be demoed or reviewed without running the agent
# and without spending anything on LLM calls.
#
#   bundle exec rake presentation_analyst:seed         # entity 157
#   bundle exec rake presentation_analyst:seed[123]    # any entity
#   bundle exec rake presentation_analyst:clear[123]   # remove seeded rows only
#
# @see db/seeds/presentation_analyst_reports.rb
namespace :presentation_analyst do
  # A local rather than a constant: defining a constant inside a namespace block
  # leaks it into Object (Lint/ConstantDefinitionInBlock).
  seed_script = Rails.root.join("db/seeds/presentation_analyst_reports.rb")

  desc "Seed fake presentation-analysis reports for a demo of the presentation analyst dashboard"
  task :seed, [:entity_id] => :environment do |_t, args|
    ENV["ENTITY_ID"] = (args[:entity_id] || 157).to_s
    load seed_script
  end

  desc "Remove only the seeded presentation-analysis reports for an entity (leaves real agent output)"
  task :clear, [:entity_id] => :environment do |_t, args|
    entity_id = (args[:entity_id] || 157).to_i
    agent = SupportAgent.find_by(agent_type: "PresentationAnalystAgent", entity_id: entity_id)
    abort "No PresentationAnalystAgent for entity #{entity_id}" unless agent

    # Match on the KEY only. A MySQL json column renders `"seeded": true` with a
    # space after the colon, so a pattern that pins the value straight after the
    # colon matches nothing — which is exactly how this silently no-opped before
    # on the equivalent portfolio_scoring:clear task.
    removed = SupportAgentReport
              .where(support_agent: agent, owner_type: "Investor")
              .where("json_fields LIKE '%\"seeded\"%'")
              .destroy_all
              .size

    Rails.logger.debug { "Removed #{removed} seeded presentation-analysis report(s) for entity #{entity_id}" }
  end
end
