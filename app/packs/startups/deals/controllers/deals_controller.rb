# frozen_string_literal: true

# Manages deal CRUD, agent settings, and the weekly summary dashboard.
class DealsController < ApplicationController
  include DealsHelper
  include AgGridHelper

  require 'pagy/extras/array'

  before_action :set_deal, only: %w[show update destroy edit overview consolidated_access_rights agent_settings update_agent_settings run_now weekly_summary update_ingest_address]
  after_action :verify_authorized, except: %i[index search investor_deals]

  # GET /deals/analytics
  def analytics
    @deals = policy_scope(Deal)
    authorize(Deal, :analytics?)
    @deals = @deals.where("tags like ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:tag])}%") if params[:tag].present?
    @deals = @deals.where("deals.archived=?", false) if params[:include_archived].blank?

    render "analytics_content", layout: false
  end

  # GET /deals or /deals.json
  def index
    @bread_crumbs = { Deals: deals_path }
    @deals = ransack_with_snapshot
    @deals = @deals.where("tags like ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:tag])}%") if params[:tag].present?
    @deals = @deals.where("deals.archived=?", false) if params[:include_archived].blank?
    @units = params[:units]
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @deals = DealIndex.filter(term: { entity_id: @entity.id })
                        .query(simple_query_string: { fields: DealIndex::SEARCH_FIELDS,
                                                      query:, default_operator: 'and' }).objects
    else
      redirect_to deals_path
    end

    render "index"
  end

  def investor_deals
    @deals = Deal.for_investor(current_user)
    @pagy, @deals = pagy(@deals)
    render "index"
  end

  def consolidated_access_rights
    @access_rights = policy_scope(AccessRight).includes(:owner, :investor, :user)

    @bread_crumbs['Access Overview'] = nil
    @deal_documents_folder = @deal.deal_documents_folder

    @access_rights = @access_rights.where(owner_id: @deal.id, owner_type: "Deal").or(@access_rights.where(owner_id: @deal_documents_folder.id, owner_type: "Folder"))
    query = params[:search][:value] if params[:search] && params[:search][:value].present?
    if query.present?
      ids = AccessRightIndex.filter(term: { entity_id: current_user.entity_id })
                            .query(simple_query_string: { fields: AccessRightIndex::SEARCH_FIELDS,
                                                          query:, default_operator: 'and' }).per(100).map(&:id)

      @access_rights = @access_rights.where(id: ids)
    end
    @access_rights = @access_rights.order(owner_type: :asc, created_at: :desc)
    @grouped_access_rights = get_grouped_access_rights(@access_rights)

    @grouped_access_rights = filter_by_owner(@grouped_access_rights, params[:access])

    if params[:all].blank?
      data = @grouped_access_rights.to_a
      per_page  = params[:per_page].to_i.nonzero? || 10
      page      = params[:page].to_i.nonzero? || 1

      @pagy     = Pagy.new(count: data.size, page: page, items: per_page, limit: per_page)
      offset    = @pagy.offset
      limit     = @pagy.respond_to?(:items) ? @pagy.items : @pagy.send(:vars)[:items]

      @paged_grouped_access_rights = data.slice(offset, limit)
    else
      @paged_grouped_access_rights = @grouped_access_rights.to_a
    end
  end

  # GET /deals/1 or /deals/1.json
  def show
    if params[:chart].present?
      render "deal_charts"
    else
      @investor_label = @deal.entity.is_fund? ? "Company" : "Investor"
      # @see WithDealIngestAddress#ensure_deal_ingest_address — lazy-creates address for pre-existing deals
      @deal_ingest_address = @deal.ensure_deal_ingest_address

      respond_to do |format|
        format.html do
          if params[:overview].present? || current_user.curr_role_investor?
            redirect_to overview_deal_path(@deal)
          else
            render "list_view"
          end
        end
        format.xlsx do
          @deal_investors = @deal.deal_investors
                                 .includes(:deal, :rich_text_notes, investor: :investor_entity, deal_activities: :rich_text_details)
          @deal_investors = @deal_investors.not_declined if [nil, "", "false", false].include?(params[:all])
          investor_ids = @deal_investors.map(&:investor_id)
          @notes = Note.where(investor_id: investor_ids, entity_id: @deal.entity_id)
                       .includes(:investor, :reminder, :rich_text_details)
                       .order(:investor_id, :on)
          response.headers['Content-Disposition'] = "attachment; filename=#{@deal.name}_list.xlsx"
          render "list_view"
        end
      end
    end
  end

  def overview; end

  # GET /deals/1/agent_settings
  def agent_settings
    authorize(@deal, :update?)
    @support_agent = find_or_initialize_deals_agent
    render "list_view"
  end

  # PATCH /deals/1/agent_settings
  def update_agent_settings
    authorize(@deal, :update?)
    agent = find_or_initialize_deals_agent

    config = (agent.json_fields || {}).merge(
      "deal_ids" => @deal.id.to_s,
      "report_recipients" => params[:report_recipients].to_s.strip,
      "stale_days" => params[:stale_days].to_s.presence || "14",
      "include_greeting" => params[:include_greeting].present? ? "true" : "false",
      "include_updates" => params[:include_updates].present? ? "true" : "false",
      "include_tasks_due" => params[:include_tasks_due].present? ? "true" : "false",
      "include_tasks_overdue" => params[:include_tasks_overdue].present? ? "true" : "false",
      "include_stale_items" => params[:include_stale_items].present? ? "true" : "false"
    )
    agent.json_fields = config

    if agent.save
      # Upsert schedule
      schedule = agent.agent_schedule || agent.build_agent_schedule
      schedule.assign_attributes(
        entity_id: @deal.entity_id,
        frequency: params[:schedule_frequency].presence || "weekly",
        run_at_time: params[:schedule_run_at_time].presence || "10:00",
        run_on_day: params[:schedule_run_on_day].to_i,
        timezone: params[:schedule_timezone].presence || "UTC",
        enabled: params.key?(:agent_enabled) ? params[:agent_enabled] == "1" : schedule.enabled
      )

      unless schedule.save
        Rails.logger.warn("[update_agent_settings] Schedule save failed for agent #{agent.id}: #{schedule.errors.full_messages.join(', ')}")
        return respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.replace("agent-settings-tab",
                                                      partial: "deals/deal_agent_settings", locals: { deal: @deal, schedule_errors: schedule.errors.full_messages })
          end
          format.html { redirect_to deal_path(@deal), alert: "Settings saved but schedule failed: #{schedule.errors.full_messages.join(', ')}" }
        end
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("agent-settings-tab",
                                                    partial: "deals/deal_agent_settings", locals: { deal: @deal })
        end
        format.html { redirect_to deal_path(@deal), notice: "Agent settings saved." }
      end
    else
      respond_to do |format|
        format.html { redirect_to deal_path(@deal), alert: "Could not save agent settings: #{agent.errors.full_messages.join(', ')}" }
      end
    end
  end

  # POST /deals/1/run_now
  def run_now
    authorize(@deal, :update?)
    agent = find_or_initialize_deals_agent
    if agent.persisted?
      SupportAgentJob.perform_later(support_agent_id: agent.id, user_id: current_user.id, execution_mode: :adhoc_batch, target_id: @deal.id, target_type: "Deal")
      redirect_to deal_path(@deal), notice: "Report queued — you'll receive an email shortly."
    else
      redirect_to deal_path(@deal), alert: "Please save agent settings first."
    end
  end

  # PATCH /deals/1/update_ingest_address
  #
  # Updates the deal's ingest email address local-part (user-choosable).
  # Restricted to company_admin (fund manager) — prevents team members
  # from changing the address and breaking the inbound flow for others.
  #
  # Responds with Turbo Stream to replace the address display inline,
  # showing validation errors if the address is taken or invalid.
  #
  # @see WithDealIngestAddress#ensure_deal_ingest_address
  def update_ingest_address
    authorize(@deal, :update?)

    # Only company admins (fund managers) can change the deal email address
    unless current_user.has_role?(:company_admin, @deal.entity)
      redirect_to deal_path(@deal), alert: "Only admins can change the deal email address"
      return
    end

    @deal_ingest_address = @deal.ensure_deal_ingest_address

    if @deal_ingest_address.update(address: params[:address].to_s.strip.downcase)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "deal-ingest-address",
            partial: "deals/deal_ingest_address",
            locals: { deal: @deal, ingest_address: @deal_ingest_address }
          )
        end
        format.html { redirect_to deal_path(@deal), notice: "Email address updated" }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "deal-ingest-address",
            partial: "deals/deal_ingest_address",
            locals: { deal: @deal, ingest_address: @deal_ingest_address }
          )
        end
        format.html { redirect_to deal_path(@deal), alert: @deal_ingest_address.errors.full_messages.join(", ") }
      end
    end
  end

  # GET /deals/1/weekly_summary
  #
  # @note Reads from the latest completed SupportAgentReport for this deal.
  #   Returns empty data hash when no agent has run yet.
  def weekly_summary
    @bread_crumbs["Weekly Summary"] = nil

    @support_agent = SupportAgent.find_by(
      entity_id: @deal.entity_id,
      agent_type: "DealManagementAgent"
    )

    @report = if params[:report_id].present?
                SupportAgentReport
                  .where(owner: @deal, support_agent: @support_agent)
                  .find_by(id: params[:report_id])
              end

    @report ||= SupportAgentReport
                .where(owner: @deal, support_agent: @support_agent)
                .where(status: %i[completed failed])
                .order(created_at: :desc)
                .first

    @data = @report&.json_fields || {}

    @past_reports = SupportAgentReport
                    .where(owner: @deal, support_agent: @support_agent)
                    .where(status: :completed)
                    .order(created_at: :desc)
                    .limit(12)
  end

  # GET /deals/new
  def new
    @bread_crumbs = { Deals: deals_path, New: nil }
    @deal = Deal.new(deal_params)
    @deal.entity_id = current_user.entity_id
    @deal.currency = @deal.entity.currency
    @deal.activity_list = Deal::ACTIVITIES
    @deal.start_date = Time.zone.today

    authorize @deal
    setup_custom_fields(@deal)
  end

  # GET /deals/1/edit
  def edit
    setup_custom_fields(@deal)
    if params[:turbo]
      frame = params[:turbo_frame_id] || "deal_form_#{@deal.id}"
      render turbo_stream: [
        turbo_stream.replace(frame, partial: "deals/form", locals: { deal: @deal, turbo_frame_id: frame, turbo: true })
      ]
    end
  end

  # POST /deals or /deals.json
  def create
    @deal = Deal.new
    # Assign form parameters to the new deal instance
    assign_deal_form_params(@deal)
    @deal.entity_id = current_user.entity_id
    authorize @deal

    results = CreateDeal.call(deal: @deal, current_user: current_user)
    respond_to do |format|
      if results.success?
        format.html { redirect_to deal_url(@deal), notice: "Deal was successfully created." }
        format.json { render :show, status: :created, location: @deal }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /deals/1 or /deals/1.json
  def update
    @frame = params[:deal][:turbo_frame_id] || "deal_form_#{@deal.id}"
    params[:deal].delete(:turbo_frame_id)
    # Assign form parameters to the existing deal instance
    assign_deal_form_params(@deal)
    respond_to do |format|
      if UpdateDeal.call(deal: @deal).success?
        @success = true
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Deal was successfully updated! Please refresh!", level: "success").broadcast
          render :update
        end
        format.html { redirect_to deal_url(@deal), notice: "Deal was successfully updated." }
        format.json { render :show, status: :ok, location: @deal }
      else
        @success = false
        @alert = "Deal could not be updated! #{@deal.errors.full_messages.join(', ')}"
        format.turbo_stream { render :update }
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /deals/1 or /deals/1.json
  def destroy
    @deal.destroy

    respond_to do |format|
      format.html { redirect_to deals_url, notice: "Deal was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Lazy-generate the single ingest address for this deal.
  # Uses the writing connection to avoid read-replica errors.
  #
  # @return [DealIngestAddress, nil]
  def ensure_deal_ingest_address
    @deal.deal_ingest_address || ActiveRecord::Base.connected_to(role: :writing) do
      DealIngestAddress.find_or_create_by(deal: @deal)
    end
  rescue ActiveRecord::RecordNotUnique
    @deal.deal_ingest_address
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_deal
    @deal = Deal.find(params[:id])
    # Use a distinct local variable name to avoid shadowing the deals_path route helper
    deals_index_path = current_user.curr_role_investor? ? deal_investors_path : deals_path
    path = if current_user.curr_role_investor?
             overview_deal_path(@deal)
           else
             deal_path(@deal)
           end
    @bread_crumbs = { Deals: deals_index_path, "#{@deal.name || '-'}": path }
    authorize(@deal)
  end

  # Only allow a list of trusted parameters through.
  def deal_params
    # Add enable_notifications and deal_investor_status to the permitted parameters
    params.require(:deal).permit(:name, :amount, :status, :form_type_id, :clone_from_id, :tags,
                                 :start_date, :currency, :units, :activity_list, :archived, :skip_templates,
                                 :grid_columns, :deal_investor_status, :enable_notifications,
                                 :analytics_stats, properties: {})
  end

  # Shared by #create and #update so both actions apply the same param-assignment
  # rules to the deal instance.
  #
  # analytics_stats is pulled out of the attrs hash and assigned separately
  # because Deal#analytics_stats= falls back to DEFAULT_ANALYTICS_STATS whenever
  # it's given a blank value. Passing it through assign_attributes unconditionally
  # would silently reset a deal's saved stat selection to the defaults any time
  # the form field is missing/blank, instead of leaving the existing value alone.
  def assign_deal_form_params(deal)
    attrs = deal_params.to_h
    stats = attrs.delete("analytics_stats")
    # deal_params permits analytics_stats as a scalar, but the hidden field's
    # StimulusJS-serialized JSON can occasionally arrive un-permitted (e.g. as part
    # of a nested structure); fall back to reading it straight off params in that case.
    stats = params[:deal][:analytics_stats] if stats.blank? && params.dig(:deal, :analytics_stats).present?

    deal.assign_attributes(attrs)
    deal.analytics_stats = stats if stats.present?
  end

  def find_or_initialize_deals_agent
    SupportAgent.find_or_initialize_by(agent_type: "DealsReportAgent", entity_id: @deal.entity_id)
  end
end
