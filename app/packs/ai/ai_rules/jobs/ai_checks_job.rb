class AiChecksJob < ApplicationJob
  queue_as :ai_checks

  def perform(owner_type, owner_id, user_id, rule_type, schedule)
    # Find the model
    model = owner_type.constantize.find(owner_id)

    send_notification("Starting #{rule_type} #{schedule} checks..", user_id, :info)
    case rule_type.underscore
    when 'compliance'
      ComplianceAssistant.run_ai_checks(model, user_id, schedule)
    when 'investor_relations'
      # InvestorRelationsAssistant.run_ai_checks(model, user_id, schedule)
    when 'investment_analyst'
      # InvestmentAnalystAssistant.run_ai_checks(model, user_id, schedule)
    else
      send_notification("Invalid rule type: #{rule_type}", user_id, :error)
      return
    end

    send_notification("Checks completed for #{model}.", user_id)
  end
end
