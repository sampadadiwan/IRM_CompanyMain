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
  # Executes the support agent job.
  #
  # EXECUTION MODES for PortfolioCompanyAgent:
  # 1. :adhoc_batch (default)
  #    - Multiple companies run sequentially without step UI
  #    - Called from portfolio_agent_run.html.erb (adhoc button)
  #    - Shows batch summary notification on completion
  #    - Enqueues single AgentChartJob for generated reports
  #
  # 2. :single_company_with_steps
  #    - Single company with step-by-step progress UI
  #    - Called from investor show page (Run Agent button)
  #    - Shows progress panel with real-time step updates
  #    - Broadcasts step completions via Turbo Stream
  #
  # 3. :scheduled (planned)
  #    - Multiple companies run silently (no UI)
  #    - Called by AgentScheduleJob (cron)
  #    - Shows "Charts generated" notification (not chat UI)
  #
  # When called without support_agent_id, enqueues jobs for all enabled agents.
  # When called with support_agent_id, executes that agent against specified or all targets.
  #
  # @param support_agent_id [Integer, nil] the ID of the support agent to run
  # @param target_id [Integer, nil] the ID of the specific target to process
  # @param target_type [String, nil] the class name of the target model
  # @param user_id [Integer, nil] the ID of the user who triggered the job
  # @param with_steps [Boolean] whether to track step-by-step progress (ignored for batch runs)
  # @param batch_ids [Array<Integer>, nil] array of IDs for batch processing
  # @param batch_ids_type [String, nil] the type of IDs provided for batch processing (must match agent's target type)
  # @param execution_mode [Symbol, nil] mode of execution (:adhoc_batch, :single_company_with_steps, :scheduled)
  # @return [void]
  def perform(support_agent_id: nil, target_id: nil, target_type: nil, user_id: nil, with_steps: false, batch_ids: nil, batch_ids_type: nil, execution_mode: :adhoc_batch)
    if support_agent_id.nil?
      support_agents = SupportAgent.enabled
      support_agents.each do |agent|
        SupportAgentJob.perform_later(support_agent_id: agent.id)
      end
    else
      support_agent = SupportAgent.find(support_agent_id)
      user = User.find(user_id) if user_id.present?
      entity = support_agent.entity

      # Create an execution log to track this run
      execution_log = AgentExecutionLog.create!(
        support_agent: support_agent,
        entity: entity,
        triggered_by: user,
        trigger_type: user_id.present? ? :manual : :scheduled,
        status: :queued,
        attempt_number: 1
      )

      begin
        execution_log.mark_running!

        # Get targets - either specific one or all from the agent
        if batch_ids.present? && batch_ids_type.present?
          # Batch processing: validate and fetch targets securely
          targets = fetch_batch_targets(support_agent, batch_ids, batch_ids_type)
          if targets.empty?
            execution_log.mark_failed!("No valid targets found for batch")
            return
          end
          # If the agent class supports a batch entrypoint, delegate the whole batch to it.
          agent_class = support_agent.agent
          if agent_class.respond_to?(:process_batch)
            # For batch runs, never use with_steps (batch runs always skip step UI)
            agent_class.process_batch(
              support_agent_id: support_agent.id,
              targets: targets,
              user_id: user_id,
              entity_id: support_agent.entity_id,
              with_steps: false,
              execution_mode: execution_mode
            )
            execution_log.mark_completed!({ batch: true, target_count: targets.count })
            return
          end
        elsif target_id.present? && target_type.present?
          targets = if target_type == "Entity" && execution_mode == :single_company_with_steps
                      # Step UI runs keep the entity as a single target so the step panel
                      # report (owner: Entity) stays in sync with the job's broadcasts.
                      [Entity.find(target_id)]
                    elsif target_type == "Entity"
                      # Scheduled/batch runs expand to individual sub-targets (e.g. Funds)
                      support_agent.agent.new.targets(target_id)
                    elsif target_type == "Investor"
                      [Investor.find(target_id)]
                    else
                      [target_type.constantize.find(target_id)]
                    end
        else
          # No target specified: run for all targets from agent's entity
          targets = support_agent.agent.new.targets(support_agent.entity_id)
          targets = targets.where(id: target_id) if target_id.present?
        end

        errors = []
        successes = []
        # A batch run is when multiple targets are processed in one job
        is_batch_run = targets.many?

        targets.each do |target|
          # Determine if this target should run with step UI
          # Only single_company_with_steps mode uses with_steps for individual targets
          target_with_steps = (execution_mode == :single_company_with_steps) && with_steps

          if target_with_steps
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
          if target_with_steps && report.present?
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

        # Mark execution log as completed
        execution_log.mark_completed!({ successes: successes.count, errors: errors.count })
      rescue StandardError => e
        Rails.logger.error { "SupportAgentJob failed: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        execution_log.mark_failed!(e.message)
      end
    end
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

    message += "<br/>✗ <strong>#{error_count}</strong> failed" if error_count.positive?

    # Show first few errors if any
    if errors.any?
      message += "<br/><br/><small class='text-muted'>Recent errors:</small>"
      errors.first(3).each do |err|
        message += "<br/><small>• #{err[:target_name] || err[:name] || err[:target_id]}: #{err[:error]}</small>"
      end
      message += "<br/><small>...and #{errors.count - 3} more</small>" if errors.count > 3
    end

    notification_type = if error_count.zero?
                          "success"
                        elsif success_count.positive?
                          "warning"
                        else
                          "danger"
                        end

    send_notification(message, user_id, notification_type)
  end

  private

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
