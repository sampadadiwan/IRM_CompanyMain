class SupportAgentJob < ApplicationJob
  queue_as :default

  def perform(support_agent_id: nil, target_id: nil, user_id: nil)

    if support_agent_id.nil?
      support_agents = SupportAgent.enabled
      support_agents.each do |agent|
        SupportAgentJob.perform_later(support_agent_id: agent.id)
      end
    else
      support_agent = SupportAgent.find(support_agent_id)
      # Get the targets for this support_agent
      targets = support_agent.agent.new.targets(support_agent.entity_id)
      # If a specific target_id is provided, filter to that target only
      targets = targets.where(id: target_id) if target_id.present?

      errors = []
      targets.each do |target|
        begin
          # Dynamically call the agent's call method with the appropriate parameters
          support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target)
          send_notification("#{support_agent.agent_type} processed Target ID=#{target.id} successfully", user_id, "success")
        rescue => e
          error_msg = "#{support_agent.agent_type} error processing Target ID=#{target.id}: #{e.message}"
          send_notification(error_msg, user_id, "danger")
          Rails.logger.error { error_msg }
          errors << { support_agent: support_agent.agent_type, target_id: target.id, error: error_msg }
        end
      end
    end




  end
end