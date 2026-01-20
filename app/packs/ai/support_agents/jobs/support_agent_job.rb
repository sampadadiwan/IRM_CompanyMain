# Background job for executing support agent tasks.
#
# Handles both batch processing of all enabled agents and single agent execution
# with optional step-by-step progress tracking.
#
# @example Run a single agent with steps
#   SupportAgentJob.perform_later(support_agent_id: 1, target_id: 5, target_type: "CapitalCall", user_id: 10, with_steps: true)
#
# @example Run all enabled agents
#   SupportAgentJob.perform_later
#
# @see SupportAgent
# @see SupportAgentService
class SupportAgentJob < ApplicationJob
  queue_as :default

  # Executes the support agent job.
  #
  # When called without support_agent_id, enqueues jobs for all enabled agents.
  # When called with support_agent_id, executes that agent against specified or all targets.
  #
  # @param support_agent_id [Integer, nil] the ID of the support agent to run
  # @param target_id [Integer, nil] the ID of the specific target to process
  # @param target_type [String, nil] the class name of the target model
  # @param user_id [Integer, nil] the ID of the user who triggered the job
  # @param with_steps [Boolean] whether to track step-by-step progress
  # @return [void]
  def perform(support_agent_id: nil, target_id: nil, target_type: nil, user_id: nil, with_steps: false)
    if support_agent_id.nil?
      support_agents = SupportAgent.enabled
      support_agents.each do |agent|
        SupportAgentJob.perform_later(support_agent_id: agent.id)
      end
    else
      support_agent = SupportAgent.find(support_agent_id)
      # Get targets - either specific one or all from the agent
      if target_id.present? && target_type.present?
        targets = [target_type.constantize.find(target_id)]
      else
        targets = support_agent.agent.new.targets(support_agent.entity_id)
        targets = targets.where(id: target_id) if target_id.present?
      end

      errors = []
      targets.each do |target|
        if with_steps
          # Initialize report with steps and pass to agent
          agent_instance = support_agent.agent.new
          report = agent_instance.initialize_report_with_steps({}, model: target, support_agent: support_agent, user_id: user_id)
          support_agent.agent.call(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: support_agent.entity_id, support_agent_report: report)
        else
          support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: support_agent.entity_id)
        end
        send_notification("#{support_agent.agent_type} processed Target ID=#{target.id} successfully", user_id, "success")
      rescue StandardError => e
        error_msg = "#{support_agent.agent_type} error processing Target ID=#{target.id}: #{e.message}"
        send_notification(error_msg, user_id, "danger")
        Rails.logger.error { error_msg }
        Rails.logger.error { e.backtrace.join("\n") }
        errors << { support_agent: support_agent.agent_type, target_id: target.id, error: error_msg }

        # Mark the report as failed so it can be re-run
        # if with_steps && defined?(report) && report.present?
        if with_steps && report.present?
          report.json_fields["final_status"] = "error"
          report.json_fields["error_message"] = e.message
          report.json_fields["completed_at"] = Time.current.iso8601
          report.status = :failed
          report.save!
        end
      end
    end
  end
end
