class FinalizePortfolioScenarioJob < ApplicationJob
  include Rails.application.routes.url_helpers
  include ApplicationHelper

  queue_as :default

  def perform(portfolio_scenario_id, user_id)
    portfolio_scenario = PortfolioScenario.find(portfolio_scenario_id)

    ActiveRecord::Base.transaction do
      result = FinalizePortfolioScenario.call(
        portfolio_scenario: portfolio_scenario
      )

      if result.success?

        # Build Ransack query params for filtering ratios by owner
        query_params = RansackQueryBuilder.multiple([[:portfolio_scenario_id, :eq, portfolio_scenario.id]])

        # Build a link to the created ratios
        ratios_link = ActionController::Base.helpers.link_to(
          "#{portfolio_scenario.name}: Ratios",
          fund_ratios_path(fund_id: portfolio_scenario.fund_id, filter: true, q: query_params),
          class: 'mb-1 badge bg-primary-subtle text-primary',
          target: '_blank',
          rel: 'noopener'
        )

        UserAlert.new(user_id:, message: "Fund ratios for #{portfolio_scenario.name} were successfully created.<br> #{ratios_link}", level: "success").broadcast
      else
        UserAlert.new(user_id:, message: "Error Finalizing Portfolio Scenario: #{portfolio_scenario.name} -  #{result[:errors].join(', ')}", level: "danger").broadcast
        errs = [portfolio_scenario: portfolio_scenario.name, error: result[:errors].join(', ')]
        EntityMailer.with(entity_id: portfolio_scenario.entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now
      end
    end
  end
end
