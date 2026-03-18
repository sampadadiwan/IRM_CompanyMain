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
  # @param batch_ids [Array<Integer>, nil] array of IDs for batch processing
  # @param batch_ids_type [String, nil] the type of IDs provided for batch processing (must match agent's target type)
  # @return [void]
  def perform(support_agent_id: nil, target_id: nil, target_type: nil, user_id: nil, with_steps: false, batch_ids: nil, batch_ids_type: nil)
    if support_agent_id.nil?
      support_agents = SupportAgent.enabled
      support_agents.each do |agent|
        SupportAgentJob.perform_later(support_agent_id: agent.id)
      end
    else
      support_agent = SupportAgent.find(support_agent_id)

      # Get targets - either specific one or all from the agent
      if batch_ids.present? && batch_ids_type.present?
        # Batch processing: validate and fetch targets securely
        targets = fetch_batch_targets(support_agent, batch_ids, batch_ids_type)
        return if targets.empty? # Safety: abort if no valid targets
      elsif target_id.present? && target_type.present?
        if target_type == "Entity"
          # Entity provided: run for all portfolio companies in that entity
          targets = support_agent.agent.new.targets(target_id, support_agent)
        elsif target_type == "Investor"
          # Specific investor provided: run for just that one
          targets = [Investor.find(target_id)]
        else
          # Other target types (for other agents like KycOnboardingAgent)
          targets = [target_type.constantize.find(target_id)]
        end
      else
        # No target specified: run for all targets from agent's entity
        targets = support_agent.agent.new.targets(support_agent.entity_id, support_agent)
        targets = targets.where(id: target_id) if target_id.present?
      end

      errors = []
      successes = []
      # A batch run is when multiple targets are processed in one job
      is_batch_run = targets.count > 1

      targets.each do |target|
        if with_steps
          # Initialize report with steps and pass to agent
          agent_instance = support_agent.agent.new
          report = agent_instance.initialize_report_with_steps({}, model: target, support_agent: support_agent, user_id: user_id)
          support_agent.agent.call(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: support_agent.entity_id, support_agent_report: report)
        else
          support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: support_agent.entity_id)
        end

        # Track successes for batch summary
        if is_batch_run
          successes << {
            id: target.id,
            name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}"
          }
        else
          # Send individual notification for non-batch or non-PortfolioCompanyAgent
          message = "#{support_agent.agent_type} processed #{target.class.name} '#{target.try(:investor_name) || target.try(:name) || "ID=#{target.id}"}' successfully"

          # Add link to view reports if this is a PortfolioCompanyAgent
          if support_agent.agent_type == "PortfolioCompanyAgent" && target.is_a?(Investor)
            # Get the support agent show page URL with the Portfolio Reports tab
            reports_url = Rails.application.routes.url_helpers.support_agent_path(
              support_agent,
              owner_id: target.id,
              owner_type: "Investor"
            )
            message += " - <a href='#{reports_url}' class='text-decoration-underline'>View Report</a>"
          end

          # For non-batch runs send immediate notifications
          send_notification(message, user_id, "success")
        end
      rescue StandardError => e
        error_msg = "#{support_agent.agent_type} error processing Target ID=#{target.id}: #{e.message}"
        Rails.logger.error { error_msg }
        Rails.logger.error { e.backtrace.join("\n") }

        error_detail = {
          support_agent: support_agent.agent_type,
          target_id: target.id,
          target_name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}",
          error: e.message
        }
        errors << error_detail

        # For batch runs, collect errors; for single runs, send immediate notification
        send_notification(error_msg, user_id, "danger") unless is_batch_run

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

      # Send summarized notification for any batch runs
      if is_batch_run
        # Use the first target's class name as the batch target type for summary
        batch_target_type = targets.first.class.name
        send_batch_summary(support_agent, successes, errors, user_id, batch_target_type)
      end
    end
  end

  private

  # Sends a summarized notification for batch Portfolio Company agent runs
  #
  # @param support_agent [SupportAgent] the agent that was run
  # @param successes [Array<Hash>] array of successful company hashes with :id and :name
  # @param errors [Array<Hash>] array of error hashes with details
  # @param user_id [Integer] the ID of the user to notify
  def send_batch_portfolio_summary(support_agent, successes, errors, user_id)
    total = successes.count + errors.count
    success_count = successes.count
    error_count = errors.count

    # Build summary message
    message = "<strong>#{support_agent.name}</strong> completed batch run:<br/>"
    message += "✓ <strong>#{success_count}</strong> of <strong>#{total}</strong> companies processed successfully"

    if error_count > 0
      message += "<br/>✗ <strong>#{error_count}</strong> failed"
    end

    # Add link to view all portfolio reports
    reports_url = Rails.application.routes.url_helpers.support_agent_path(
      support_agent,
      anchor: "portfolio-reports"
    )
    message += "<br/><a href='#{reports_url}' class='text-decoration-underline'>View All Portfolio Reports →</a>"

    # Show first few errors if any
    if errors.any?
      message += "<br/><br/><small class='text-muted'>Recent errors:</small>"
      errors.first(3).each do |err|
        message += "<br/><small>• #{err[:target_name]}: #{err[:error]}</small>"
      end
      message += "<br/><small>...and #{errors.count - 3} more</small>" if errors.count > 3
    end

    # Determine notification type based on results
    notification_type = if error_count == 0
                          "success"
                        elsif success_count > 0
                          "warning" # Some succeeded, some failed
                        else
                          "danger" # All failed
                        end

    send_notification(message, user_id, notification_type)

    # Use SupportAgentService to broadcast table refresh
    # This reloads only the portfolio companies table frame, keeping the notification visible
    # SupportAgentService.new.broadcast_portfolio_table_refresh(user_id)
  end

  # Sends a summarized notification for batch runs across multiple target types
  # This is a generic replacement for portfolio-only summaries and builds a
  # contextual link based on the provided batch_target_type.
  def send_batch_summary(support_agent, successes, errors, user_id, batch_target_type)
    total = successes.count + errors.count
    success_count = successes.count
    error_count = errors.count

    # Build summary message
    message = "<strong>#{support_agent.name}</strong> completed batch run for #{batch_target_type.pluralize}:<br/>"
    message += "✓ <strong>#{success_count}</strong> of <strong>#{total}</strong> processed successfully"

    if error_count > 0
      message += "<br/>✗ <strong>#{error_count}</strong> failed"
    end

    # Show first few errors if any
    if errors.any?
      message += "<br/><br/><small class='text-muted'>Recent errors:</small>"
      errors.first(3).each do |err|
        message += "<br/><small>• #{err[:target_name] || err[:name] || err[:target_id]}: #{err[:error]}</small>"
      end
      message += "<br/><small>...and #{errors.count - 3} more</small>" if errors.count > 3
    end

    notification_type = if error_count == 0
                          "success"
                        elsif success_count > 0
                          "warning"
                        else
                          "danger"
                        end

    send_notification(message, user_id, notification_type)
  end

  # Fetches batch targets securely with entity validation and type checking
  #
  # @param support_agent [SupportAgent] the agent being run
  # @param batch_ids [Array<Integer>] array of target IDs
  # @param batch_ids_type [String] the type of targets (must be whitelisted)
  # @return [ActiveRecord::Relation] validated and scoped targets
  def fetch_batch_targets(support_agent, batch_ids, batch_ids_type)
    # Security: Whitelist allowed target types to prevent arbitrary class instantiation
    allowed_types = {
      "Investor" => Investor,
      "InvestorKyc" => InvestorKyc,
      "CapitalCall" => CapitalCall,
      "Fund" => Fund
      # Add other valid target types as needed
    }

    # Validate the type is allowed
    unless allowed_types.key?(batch_ids_type)
      Rails.logger.error "SupportAgentJob: Invalid batch_ids_type '#{batch_ids_type}'. Must be one of: #{allowed_types.keys.join(', ')}"
      return []
    end

    target_class = allowed_types[batch_ids_type]

    # Security: Ensure all targets belong to the same entity as the support agent
    # This prevents cross-entity data access
    targets = target_class.where(id: batch_ids, entity_id: support_agent.entity_id)

    # Log security event if some IDs were filtered out (potential unauthorized access attempt)
    if targets.count < batch_ids.count
      filtered_count = batch_ids.count - targets.count
      Rails.logger.warn "SupportAgentJob: Filtered #{filtered_count} unauthorized #{batch_ids_type} IDs for entity #{support_agent.entity_id}"
    end

    targets
  end
end
