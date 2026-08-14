# frozen_string_literal: true

# Demo data for the Portfolio Scoring Dashboard.
#
# Fabricates SupportAgentReport rows in the shape PortfolioScoringAgent#store_score
# writes, so the dashboard can be demoed or reviewed without running the agent
# and without spending anything on LLM calls.
#
#   bundle exec rake portfolio_scoring:seed         # entity 157
#   bundle exec rake portfolio_scoring:seed[123]    # any entity
#   bundle exec rake portfolio_scoring:clear[123]   # remove seeded rows only
#
# @see db/seeds/portfolio_scoring_reports.rb
namespace :portfolio_scoring do
  SEED_SCRIPT = Rails.root.join("db/seeds/portfolio_scoring_reports.rb")

  desc "Seed fake portfolio scoring reports for a demo of the scoring dashboard"
  task :seed, [:entity_id] => :environment do |_t, args|
    ENV["ENTITY_ID"] = (args[:entity_id] || 157).to_s
    load SEED_SCRIPT
  end

  desc "Remove only the seeded scoring reports for an entity (leaves real agent output)"
  task :clear, [:entity_id] => :environment do |_t, args|
    entity_id = (args[:entity_id] || 157).to_i
    agent = SupportAgent.find_by(agent_type: "PortfolioScoringAgent", entity_id: entity_id)
    abort "No PortfolioScoringAgent for entity #{entity_id}" unless agent

    # Match on the KEY only. A MySQL json column renders `"seeded": true` with a
    # space after the colon, so a pattern that pins the value straight after the
    # colon matches nothing — which is exactly how this silently no-opped before.
    removed = SupportAgentReport
              .where(support_agent: agent, owner_type: "Investor")
              .where("json_fields LIKE '%\"seeded\"%'")
              .destroy_all
              .size

    Rails.logger.debug { "Removed #{removed} seeded scoring report(s) for entity #{entity_id}" }
  end
end
