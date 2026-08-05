# frozen_string_literal: true

# Background job for running PortfolioCompanyAgent validation from the dashboard.
#
# This job exists because the dashboard needs to pass check_as_on_date (manual
# period selection) to PortfolioCompanyAgent.process_batch, and the shared
# SupportAgentJob doesn't accept agent-specific parameters.
#
# By keeping this in the portfolio_company_dashboard pack, we avoid modifying
# shared support_agents framework files (SupportAgentJob, SupportAgentService).
#
# @see PortfolioCompanyAgent#process_batch
# @see PortfolioCompanyDashboardController#run_validation
class PortfolioValidationJob < ApplicationJob
  queue_as :agents

  # @param support_agent_id [Integer] the PortfolioCompanyAgent's SupportAgent record ID
  # @param user_id [Integer] the FM who triggered the run
  # @param entity_id [Integer] the entity scope
  # @param check_as_on_date [String, nil] ISO date string for manual period override (e.g., "2026-06-30");
  #   nil means auto-compute the most recently completed period
  # @param target_ids [Array<Integer>, nil] specific investor IDs to validate;
  #   nil means all portfolio companies for the entity
  def perform(support_agent_id:, user_id:, entity_id:, check_as_on_date: nil, target_ids: nil)
    # Parse the date string back to a Date object (Sidekiq serializes as string).
    check_date = check_as_on_date.present? ? Date.parse(check_as_on_date) : nil

    # Resolve targets — specific companies if target_ids provided, otherwise all.
    # Re-scopes by entity_id + category as a safety guard against stale/tampered IDs.
    targets = if target_ids.present?
                Investor.where(id: target_ids, entity_id: entity_id)
                        .where("LOWER(category) = ?", "portfolio company")
              else
                PortfolioCompanyAgent.new.targets(entity_id)
              end

    PortfolioCompanyAgent.process_batch(
      support_agent_id: support_agent_id,
      targets: targets,
      user_id: user_id,
      entity_id: entity_id,
      execution_mode: :adhoc_batch,
      check_as_on_date: check_date
    )
  end
end
