# Controller for managing Support Agents and their execution.
#
# Provides CRUD operations for SupportAgent records and handles
# agent execution with step-by-step progress tracking via Turbo Streams.
#
# @see SupportAgent
# @see SupportAgentJob
# @see SupportAgentReport
class SupportAgentsController < ApplicationController
  before_action :set_support_agent, only: %i[show edit update destroy]

  # Lists all support agents accessible by the current user.
  # Also computes a setup preview for the "Setup All Agents" modal when the user has permission.
  #
  # @return [void]
  def index
    @q = SupportAgent.ransack(params[:q])
    @support_agents = policy_scope(@q.result)
    @setup_preview  = compute_setup_preview if policy(:support_agent).setup?
  end

  # Renders the LLM API key configuration screen.
  #
  # @return [void]
  def llm_keys
    authorize :support_agent, :llm_keys?
    @entity_setting = current_user.entity.entity_setting
  end

  # Saves LLM API keys and the default model to EntitySetting.
  # Blank key fields are skipped (existing key preserved) unless the
  # matching clear_* checkbox is checked (explicit removal).
  #
  # @return [void]
  def update_llm_keys
    authorize :support_agent, :update_llm_keys?
    @entity_setting = current_user.entity.entity_setting

    attrs = {}
    LlmModels::PROVIDERS.each_value do |provider|
      field = provider[:key_field].to_s
      submitted_value = params.dig(:entity_setting, field)
      clear_checked   = params.dig(:entity_setting, "clear_#{field}") == "1"

      if clear_checked
        attrs[field] = nil # explicit removal
      elsif submitted_value.present?
        attrs[field] = submitted_value.strip # new value
      end
      # blank + not clearing → omit from attrs (keep existing)
    end

    default_model = params.dig(:entity_setting, :default_llm_model)
    attrs[:default_llm_model] = default_model.presence

    if @entity_setting.update(attrs)
      redirect_to llm_keys_support_agents_path, notice: "LLM keys saved."
    else
      render :llm_keys, status: :unprocessable_entity
    end
  end

  # Runs SupportAgentsSetupService for the current entity.
  # Idempotent — creates missing agents, extends existing ones, never overwrites UI-configured values.
  #
  # @return [void]
  def setup
    authorize :support_agent, :setup?
    SupportAgentsSetupService.new(current_user.entity_id).call
    redirect_to support_agents_path, notice: "Support agents provisioned successfully."
  rescue StandardError => e
    redirect_to support_agents_path, alert: "Setup failed: #{e.message}"
  end

  # Displays a single support agent.
  #
  # @return [void]
  def show
    # @support_agent is already set and authorized by set_support_agent before_action

    # Load schedule for the Schedule tab
    @agent_schedule = AgentSchedule.find_by(
      support_agent: @support_agent,
      entity_id: @support_agent.entity_id
    )

    # Load execution logs for the Execution History tab
    @execution_logs = AgentExecutionLog
                      .for_agent_entity(@support_agent.id, @support_agent.entity_id)
                      .recent
                      .limit(20)

    query = AgentReportsQuery.new(@support_agent, params)
    @fund_reports         = query.fund_reports
    @portfolio_reports    = query.portfolio_reports
    @scoring_reports      = query.scoring_reports
    @note_summaries       = query.note_summaries
    @presentation_reports = query.presentation_reports
    @deal_reports         = query.deal_reports
    @rta_reports          = query.rta_reports
    @side_letter_obligations = query.side_letter_obligations
  end

  # Initializes a new support agent for creation.
  #
  # @return [void]
  def new
    @support_agent = SupportAgent.new(support_agent_params)
    @support_agent.entity_id = current_user.entity_id
    authorize @support_agent
  end

  # Renders the edit form for a support agent.
  #
  # @return [void]
  def edit; end

  # Creates a new support agent.
  #
  # @return [void]
  def create
    @support_agent = SupportAgent.new(support_agent_params)
    @support_agent.entity_id = current_user.entity_id
    merge_chat_config
    authorize @support_agent
    if @support_agent.save
      redirect_to @support_agent, notice: "Support agent was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Updates an existing support agent.
  #
  # @return [void]
  def update
    @support_agent.assign_attributes(support_agent_params)
    merge_chat_config
    if @support_agent.save
      redirect_to @support_agent, notice: "Support agent was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deletes a support agent.
  #
  # @return [void]
  def destroy
    @support_agent.destroy!
    redirect_to support_agents_url, notice: "Support agent was successfully destroyed.", status: :see_other
  end

  # Renders note summaries for the NoteSummarizerAgent via a lazy Turbo Frame.
  # Used by the dashboard widget on the Portfolio Company and Investor dashboards.
  #
  # @return [void]
  def note_summaries
    entity_id = params[:entity_id].presence || current_user.entity_id
    @support_agent = SupportAgent.find_by!(agent_type: "NoteSummarizerAgent", entity_id: entity_id)
    authorize @support_agent, :show?

    reports = SupportAgentReport
              .where(support_agent: @support_agent, owner_type: "Investor")
              .includes(:owner)
    reports = reports.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @note_summaries = reports.order(updated_at: :desc).limit(20)
  end

  # Updates the score JSON of a PortfolioScoringAgent report inline.
  # Authorization is performed against the report's owner (Investor) rather than
  # the SupportAgent, so any user with investor-edit permission can refine the score.
  #
  # @return [void]
  def update_score
    report   = SupportAgentReport.find(params[:report_id])
    investor = report.owner
    authorize investor, :update?

    updated_score = (report.json_fields["score"] || {}).merge(score_edit_params)
    report.json_fields = report.json_fields.merge(
      "score" => updated_score,
      "manually_edited" => true,
      "edited_at" => Time.current.iso8601
    )
    report.save!

    render json: { status: "ok", edited_at: report.json_fields["edited_at"] }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # Updates the summary_text of a NoteSummarizerAgent report inline.
  # Authorization is performed against the report's owner (Investor).
  #
  # @return [void]
  def update_note_summary
    report   = SupportAgentReport.find(params[:report_id])
    investor = report.owner
    authorize investor, :update?

    summary_text = params.permit(:summary_text)[:summary_text].to_s.strip
    report.json_fields = report.json_fields.merge(
      "summary_text" => summary_text,
      "manually_edited" => true,
      "edited_at" => Time.current.iso8601
    )
    report.save!

    render json: { status: "ok", edited_at: report.json_fields["edited_at"] }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # Enqueues a support agent job for execution.
  # When a specific target is supplied and the request is Turbo, initialises a
  # step-tracked report and streams the progress panel back so the caller gets
  # real-time updates without a page reload.
  #
  # @return [void]
  def run
    @support_agent = SupportAgent.find_by(agent_type: params[:agent_type], entity_id: current_user.entity_id)
    authorize @support_agent

    target = resolve_target(params[:target_type], params[:target_id])

    # RtaReconciliationAgent: save the uploaded PDF as a Document now (before the async job runs)
    rta_pdf_document_id = nil
    if params[:agent_type] == "RtaReconciliationAgent" && params[:rta_pdf].present?
      doc = Document.new(
        name: "RTA Statement (PDF)",
        entity: current_user.entity,
        owner: target,
        user: current_user,
        send_email: false,
        orignal: true
      )
      doc.file = params[:rta_pdf]
      doc.save!
      rta_pdf_document_id = doc.id
    end

    # RemittanceReconciliationAgent: save the uploaded bank statement xlsx as a Document now
    # (before the async job runs), same pattern as the RTA PDF above.
    bank_statement_document_id = nil
    if params[:agent_type] == "RemittanceReconciliationAgent" && params[:bank_statement].present?
      doc = Document.new(
        name: "Bank Statement",
        entity: current_user.entity,
        owner: target,
        user: current_user,
        send_email: false,
        orignal: true
      )
      doc.file = params[:bank_statement]
      doc.save!
      bank_statement_document_id = doc.id
    end

    if target
      steps = @support_agent.agent.step_definitions.map do |s|
        { "step" => s[:step], "id" => s[:id], "label" => s[:label], "short_label" => s[:short_label], "status" => "pending" }
      end
      @report = SupportAgentReport.find_or_initialize_by(owner: target, support_agent: @support_agent)
      @report.assign_attributes(
        status: :pending,
        json_fields: { "steps" => steps, "final_status" => "running", "triggered_by" => "manual",
                       "triggered_by_user_id" => current_user.id, "run_at" => Time.current.iso8601 }
      )
      @report.save!
    end

    # Forward optional estimated_closing_date from the run modal — used by
    # CP/CS agent to calculate obligation due dates relative to Closing.
    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      target_id: params[:target_id],
      target_type: params[:target_type],
      user_id: current_user.id,
      with_steps: target.present?,
      execution_mode: target.present? ? :single_company_with_steps : :adhoc_batch,
      rta_pdf_document_id: rta_pdf_document_id,
      bank_statement_document_id: bank_statement_document_id,
      estimated_closing_date: params[:estimated_closing_date].presence
    )

    respond_to do |format|
      format.html { redirect_to(request.referer || support_agents_path, notice: "Support agent job has been queued.") }
      format.turbo_stream do
        if target && @report
          # Replace the report panel by its ID, and also the host page's
          # fixed wrapper so the first run and re-runs both land in a
          # single, predictable target. CP/CS uses cp_cs_progress_wrapper
          # (PI show page); SLO uses slo_progress_wrapper (commitment page).
          panel_locals = { report: @report, support_agent: @support_agent, target: target }
          wrapper_id = @support_agent.agent_type == "SideLetterObligationAgent" ? "slo_progress_wrapper" : "cp_cs_progress_wrapper"
          render turbo_stream: [
            turbo_stream.replace("progress_panel_#{@report.id}",
                                 partial: "support_agents/progress_panel",
                                 locals: panel_locals),
            turbo_stream.replace(wrapper_id,
                                 partial: "support_agents/progress_panel",
                                 locals: panel_locals)
          ]
        else
          flash.now[:notice] = "Support agent job has been queued."
          render turbo_stream: turbo_stream.replace("page_alerts", partial: "layouts/alerts")
        end
      end
    end
  end

  # Runs the agent with step-by-step progress tracking.
  #
  # EXECUTION MODE: Single Company with Steps (shows progress UI)
  # - Called for single portfolio company runs (e.g., from investor show page)
  # - Shows step-by-step progress panel with real-time updates
  # - Broadcasts progress updates as each step completes
  # - Renders progress panel partial with Turbo Stream response
  #
  # Initializes steps from the agent's step definitions and creates/updates
  # a SupportAgentReport to track progress. Responds with Turbo Stream updates
  # for real-time UI feedback.
  #
  # @return [void]
  def run_with_steps
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    target = find_target(params[:target_type], params[:target_id])
    return render json: { status: "error", message: "Target not found" }, status: :not_found unless target

    # When target is an Entity, check if the agent expands it into multiple sub-targets.
    # If so, run as batch with live progress panel instead of step UI.
    if params[:target_type] == "Entity"
      batch_targets = @support_agent.agent.new.targets(params[:target_id].to_i)
      target_count = batch_targets.respond_to?(:count) ? batch_targets.count : batch_targets.size

      if target_count > 1
        SupportAgentJob.perform_later(
          support_agent_id: @support_agent.id,
          target_id: params[:target_id],
          target_type: params[:target_type],
          user_id: current_user.id,
          with_steps: true,
          execution_mode: :adhoc_batch
        )

        respond_to do |format|
          format.html { redirect_to(request.referer || support_agents_path, notice: "#{@support_agent.name} queued.") }
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace(
              "batch_progress_panel",
              partial: "support_agents/batch_progress_panel",
              locals: {
                support_agent: @support_agent,
                current: 0,
                total: target_count,
                target_name: nil,
                successes: 0,
                errors: 0,
                status: :queued
              }
            )
          end
        end
        return
      end
    end

    # Enqueue the job with execution_mode = single_company_with_steps
    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      target_id: params[:target_id],
      target_type: params[:target_type],
      user_id: current_user.id,
      with_steps: true,
      execution_mode: :single_company_with_steps
    )

    # Resolve the actual target the same way the job will — when the agent
    # expands an Entity into a single sub-target (e.g. Deal), the report
    # owner must match so the Turbo Stream subscription channel aligns.
    resolved_target = if params[:target_type] == "Entity"
                        expanded = @support_agent.agent.new.targets(params[:target_id].to_i)
                        count = expanded.respond_to?(:count) ? expanded.count : expanded.size
                        count == 1 && !expanded.first.is_a?(Entity) ? expanded.first : target
                      else
                        target
                      end

    # Return the report info for Turbo Stream subscription
    # Initialize steps from the agent's step definitions
    steps = @support_agent.agent.step_definitions.map do |step_def|
      {
        "step" => step_def[:step],
        "id" => step_def[:id],
        "label" => step_def[:label],
        "short_label" => step_def[:short_label],
        "status" => "pending"
      }
    end

    report = SupportAgentReport.find_or_initialize_by(owner: resolved_target, support_agent: @support_agent)

    report.status = :pending
    report.json_fields = {
      "steps" => steps,
      "final_status" => "running",
      "run_at" => Time.current.iso8601
    }
    report.save!

    respond_to do |format|
      format.html { redirect_to(request.referer || support_agents_path, notice: "Support agent job has been queued.") }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "progress_panel_new",
          partial: "support_agents/progress_panel",
          locals: { report: report, support_agent: @support_agent, target: target }
        )
      end

      format.json do
        render json: {
          status: "started",
          report_id: report.id,
          stream: "support_agent_report_#{report.id}",
          steps: @support_agent.agent.step_definitions
        }, status: :accepted
      end
    end
  end

  # Runs the support agent on multiple portfolio companies in batch (adhoc run).
  #
  # EXECUTION MODE: Batch (no step-by-step UI)
  # - Called from portfolio_agent_run.html.erb when user clicks "Run Agent on Selected Companies"
  # - Processes multiple companies sequentially without steps UI
  # - Shows a batch summary notification when complete
  # - For PortfolioCompanyAgent: enqueues a single AgentChartJob at the end
  #
  # Queues a single job that will process all specified companies and send
  # a summarized notification when complete.
  #
  # @return [void]
  def run_batch
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    # Generic batch processing - get target IDs and type
    target_ids = params[:target_ids]&.reject(&:blank?) || []
    target_type = params[:target_type] || infer_target_type_from_agent(@support_agent)

    if target_ids.empty?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "No targets selected"
          render turbo_stream: turbo_stream.replace(
            "page_alerts",
            partial: "layouts/alerts"
          )
        end
        format.html do
          redirect_to(request.referer || support_agents_path, alert: "No targets selected")
        end
      end
      return
    end

    # Validate target type is supported
    unless valid_target_type?(target_type)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Invalid target type: #{target_type}"
          render turbo_stream: turbo_stream.replace(
            "page_alerts",
            partial: "layouts/alerts"
          )
        end
        format.html do
          redirect_to(request.referer || support_agents_path, alert: "Invalid target type")
        end
      end
      return
    end

    # Queue the batch job - it will process all targets and send one summary notification
    # NOTE: with_steps is always false for adhoc batch runs (no step UI for multiple companies)
    SupportAgentJob.perform_later(
      support_agent_id: @support_agent.id,
      target_type: target_type,
      target_id: target_ids.first, # First ID for context
      user_id: current_user.id,
      with_steps: false,
      batch_ids: target_ids,
      batch_ids_type: target_type,
      execution_mode: :adhoc_batch
    )

    # Determine friendly name for the target type
    target_name = target_type_display_name(target_type)

    respond_to do |format|
      format.html do
        redirect_to(
          request.referer || support_agents_path,
          notice: "Agent queued for #{target_ids.count} #{target_name.pluralize(target_ids.count)}. You'll receive a summary notification when complete."
        )
      end

      format.turbo_stream do
        flash.now[:notice] = "Agent queued for #{target_ids.count} #{target_name.pluralize(target_ids.count)}. You'll receive a summary notification when complete."
        render turbo_stream: turbo_stream.replace(
          "page_alerts",
          partial: "layouts/alerts"
        )
      end
    end
  end

  # Cancels a running agent execution.
  #
  # Updates the report status to failed and records cancellation metadata.
  #
  # @return [void]
  def cancel
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    report = SupportAgentReport.find(params[:report_id])

    return render json: { status: "error", message: "Agent is not running" }, status: :unprocessable_entity unless report.running?

    report.json_fields["cancelled_at"] = Time.current.iso8601
    report.json_fields["cancelled_by_user_id"] = current_user.id
    report.json_fields["final_status"] = "cancelled"
    report.status = :failed
    report.save!

    respond_to do |format|
      format.html { redirect_to(request.referer || support_agents_path, notice: "Agent cancelled.") }
      format.json { render json: { status: "cancelled", cancelled_at: report.json_fields["cancelled_at"] } }
    end
  end

  # Returns the current execution status for a target.
  #
  # @return [void]
  def status
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    target = find_target(params[:target_type], params[:target_id])
    return render json: { status: "error", message: "Target not found" }, status: :not_found unless target

    report = SupportAgentReport.find_by(owner: target, support_agent: @support_agent)

    if report.nil?
      render json: { report_id: nil, final_status: "never_run" }
    else
      render json: {
        report_id: report.id,
        final_status: report.final_status,
        run_at: report.run_at&.iso8601,
        steps: report.steps,
        failed_step: report.json_fields["failed_step"]
      }
    end
  end

  # Returns the step details partial for a specific step.
  #
  # @return [void]
  def step_details
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent

    report = SupportAgentReport.find(params[:report_id])
    step_num = params[:step_num].to_i

    step = report.steps.find { |s| s["step"] == step_num }

    if step
      render partial: "support_agents/step_details", locals: { step: step, report: report, support_agent: @support_agent }
    else
      render plain: "Step not found", status: :not_found
    end
  end

  # Returns a Turbo Frame with step transition checkboxes for the selected deal.
  # Called via AJAX when the deal selector changes in the DealManagementAgent config partial.
  # Works as both a member route (persisted agent, edit form) and collection route (new agent form).
  #
  # @param id [Integer] optional — the support agent's ID (member route only)
  # @param deal_id [Integer] query param — the selected deal's ID
  # @return [void] renders the _deal_steps_frame partial inside a Turbo Frame
  def deal_steps
    if params[:id]
      @support_agent = SupportAgent.find(params[:id])
      authorize @support_agent, :edit?
    else
      @support_agent = SupportAgent.new(entity_id: current_user.entity_id)
      authorize @support_agent, :new?
    end

    # Scope to current entity to prevent cross-entity deal data leakage via collection route
    deal = Deal.find_by(id: params[:deal_id], entity_id: current_user.entity_id)
    templates = deal ? DealActivity.where(deal_id: deal.id, deal_investor_id: nil).order(:sequence).to_a : []

    transition_pairs = templates.each_cons(2).map do |from_step, to_step|
      {
        value: "#{from_step.sequence}-#{to_step.sequence}",
        label: "#{from_step.title} → #{to_step.title}"
      }
    end
    if templates.any?
      last_step = templates.last
      transition_pairs << {
        value: "#{last_step.sequence}-0",
        label: "#{last_step.title} → Completed"
      }
    end

    render partial: "support_agents/deal_steps_frame",
           locals: { deal: deal, transition_pairs: transition_pairs, selected: Set.new }
  end

  private

  # Merges chat configuration params into the support agent's json_fields.
  # Chat config fields (enabled, model, provider_type, system_prompt) are submitted
  # as top-level params under `chat_config[...]` and need to be merged into
  # json_fields["chat_config"] without overwriting other existing json_fields keys.
  def merge_chat_config
    return if params[:chat_config].blank?

    chat_cfg = params[:chat_config].permit(:enabled).to_h
    chat_cfg["enabled"] = chat_cfg["enabled"] == "true"

    existing = (@support_agent.json_fields || {}).deep_dup # deep_dup so Rails detects the change
    existing["chat_config"] = (existing["chat_config"] || {}).merge(chat_cfg)
    @support_agent.json_fields = existing
  end

  # Finds a target record by type and ID.
  #
  # Special handling for Portfolio Company Agent:
  # - If target_type is "Entity", returns the first portfolio company (for UI display)
  #   but the job will process all portfolio companies matching filters
  # - If target_type is "Investor", returns that specific investor
  #
  # @param target_type [String] the class name of the target
  # @param target_id [Integer, String] the ID of the target record
  # @return [ApplicationRecord, nil] the target record or nil if not found
  def find_target(target_type, target_id)
    return nil unless target_type.present? && target_id.present?

    if target_type == "Entity" && @support_agent&.agent_type == "PortfolioCompanyAgent"
      # For Portfolio Company Agent with Entity target, return first portfolio company
      # This is used to display the progress panel UI for the batch run
      # The job will handle fetching all portfolio companies based on filters
      targets = @support_agent.agent.new.targets(target_id)
      targets.first # Return first portfolio company for UI purposes
    else
      # Standard case: return the exact target
      target_type.constantize.find_by(id: target_id)
    end
  rescue NameError
    nil
  end

  # Sets the support agent and authorizes access.
  #
  # @return [void]
  def set_support_agent
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent
    @bread_crumbs = { 'Support Agents': support_agents_path, "#{@support_agent.name}": support_agent_path(@support_agent) }
  end

  # Permits trusted parameters for support agent creation/update.
  # Merges submitted json_fields and properties into the existing record's json_fields
  # to prevent silent data loss of keys not represented in the form.
  #
  # @return [ActionController::Parameters] permitted parameters
  def support_agent_params
    return {} unless params.key?(:support_agent)

    permitted = params.require(:support_agent).permit(
      :name, :description, :category, :entity_id, :form_type_id, :agent_type, :json_fields,
      :document_folder_id, :with_steps, :enabled, :llm_model,
      properties: {},
      documents_attributes: Document::NESTED_ATTRIBUTES
    )

    # Build merged json_fields: existing DB values → properties (custom form fields) → hidden field JSON.
    # Properties go first so step toggles are captured; hidden field JSON goes last because
    # it is the Stimulus-managed source of truth for agent-specific config (deal_ids, preset_steps, funds).
    existing = (@support_agent&.json_fields || {}).deep_dup
    # Always delete :properties to prevent assign_attributes from overwriting json_fields via alias
    props = permitted.delete(:properties)
    existing.merge!(props.to_h) if props.present?

    if permitted[:json_fields].is_a?(String) && permitted[:json_fields].start_with?("{")
      begin
        existing.merge!(JSON.parse(permitted[:json_fields]))
      rescue JSON::ParserError => e
        Rails.logger.warn "[SupportAgentsController] Invalid json_fields JSON: #{e.message}"
      end
    end

    permitted[:json_fields] = existing
    permitted
  end

  # Permits score fields submitted from the inline editor.
  def score_edit_params
    params.require(:score).permit(
      :overall_score, :grade, :summary,
      strengths: [], risks: [], recommendations: [],
      dimensions: [:name, :score, :weight, :rationale, { positives: [], concerns: [] }]
    ).to_h
  end

  # Infers the target type from the agent's targets method.
  # Calls the agent's targets method and extracts the model class name.
  #
  # @param support_agent [SupportAgent] the agent to check
  # @return [String] the target model class name (e.g., "Investor", "CapitalCall")
  def infer_target_type_from_agent(support_agent)
    # Get the agent service class
    agent_service = support_agent.agent_service
    return nil unless agent_service.respond_to?(:targets)

    # Call targets with entity_id to get the relation
    # Use a safe call with current user's entity
    target_relation = if agent_service.method(:targets).arity == 1
                        agent_service.targets(current_user.entity_id)
                      elsif agent_service.method(:targets).arity == 2
                        agent_service.targets(current_user.entity_id, support_agent)
                      else
                        agent_service.targets
                      end

    # Extract the model class name from the relation
    target_relation.model.name if target_relation.respond_to?(:model)
  rescue StandardError => e
    Rails.logger.error "[SupportAgentsController] Failed to infer target type: #{e.message}"
    nil
  end

  # Validates that the target type is in the allowed whitelist.
  #
  # @param target_type [String] the target model class name
  # @return [Boolean] true if valid
  def valid_target_type?(target_type)
    # Must match the whitelist in SupportAgentJob
    allowed_types = %w[Investor InvestorKyc CapitalCall Fund]
    allowed_types.include?(target_type)
  end

  # Resolves a target record from type + id params without special-casing.
  # Returns nil if either param is blank or the class cannot be resolved.
  def resolve_target(target_type, target_id)
    return nil if target_type.blank? || target_id.blank?

    target_type.constantize.find_by(id: target_id)
  rescue NameError
    nil
  end

  # Computes what SupportAgentsSetupService will do for the current entity without executing.
  # Returns an array of hashes, one per config entry, each with:
  #   :tag    — agent_type string
  #   :name   — human name (from config or existing agent)
  #   :status — :create | :update | :extend | :current | :skipped
  #   :detail — human-readable one-liner describing the pending change
  def compute_setup_preview
    entity_id = current_user.entity_id

    SupportAgentsSetupService::SUPPORT_AGENT_FORM_CONFIGS.filter_map do |cfg|
      tag = cfg[:tag]

      if cfg[:extend_only]
        ft = FormType.find_by(entity_id: entity_id, name: "SupportAgent", tag: tag)
        unless ft
          next { tag: tag, name: tag.humanize, status: :skipped,
                 detail: "FormType not found — agent not yet provisioned" }
        end

        existing_names = ft.form_custom_fields.pluck(:name)
        new_fields     = cfg[:fields].reject { |f| existing_names.include?(f[:name]) }

        if new_fields.any?
          { tag: tag, name: tag.humanize, status: :extend,
            detail: "#{new_fields.size} new field(s) will be added: #{new_fields.map { |f| f[:name] }.join(', ')}" }
        else
          { tag: tag, name: tag.humanize, status: :current, detail: "All fields already configured" }
        end

      else
        agent_cfg = cfg[:agent]
        sa        = SupportAgent.find_by(entity_id: entity_id, agent_type: tag)

        if sa.nil?
          { tag: tag, name: agent_cfg[:name], status: :create,
            detail: "New agent will be created" }
        else
          incoming_keys = (agent_cfg[:json_fields] || {}).keys
          missing_keys  = incoming_keys - (sa.json_fields || {}).keys
          if missing_keys.any?
            { tag: tag, name: agent_cfg[:name], status: :update,
              detail: "#{missing_keys.size} new config key(s) will be merged: #{missing_keys.join(', ')}" }
          else
            { tag: tag, name: agent_cfg[:name], status: :current, detail: "Already fully configured" }
          end
        end
      end
    end
  end

  # Returns a human-friendly display name for the target type.
  #
  # @param target_type [String] the target model class name
  # @return [String] display name
  def target_type_display_name(target_type)
    case target_type
    when "Investor"
      "company"
    when "InvestorKyc"
      "KYC record"
    when "CapitalCall"
      "capital call"
    when "Fund"
      "fund"
    else
      target_type.underscore.humanize.downcase
    end
  end
end
