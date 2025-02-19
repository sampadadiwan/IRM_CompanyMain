class DealActivitiesController < ApplicationController
  include DealInvestorsHelper
  before_action :set_deal_activity, only: %w[show update destroy edit update_sequence toggle_completed perform_activity_action]
  skip_before_action :verify_authenticity_token, only: %i[update_sequence perform_activity_action update_sequences], raise: false
  after_action :verify_authorized, except: %w[update_sequences]

  # GET /deal_activities or /deal_activities.json
  def index
    authorize(DealActivity)
    @deal_activities = policy_scope(DealActivity).includes(:deal, deal_investor: :investor)

    @deal_activities = @deal_activities.where(deal_id: params[:deal_id]) if params[:deal_id].present?

    @deal_activities = @deal_activities.where(deal_investor_id: params[:deal_investor_id]) if params[:deal_investor_id].present?

    # Show only templates
    @deal_activities = if params[:template].present?
                         @deal_activities.where(deal_investor_id: nil).order(sequence: :asc)
                       else
                         @deal_activities.where.not(deal_investor_id: nil).order(sequence: :asc)
                       end
    @deal_activities = @deal_activities.page params[:page] if params[:all].blank?
  end

  def search
    @entity = current_user.entity
    @deal_activities = DealActivity.search(params[:query].to_s, star: false, with: { entity_id: current_user.entity_id })

    render "index"
  end

  # GET /deal_activities/1 or /deal_activities/1.json
  def show
    authorize @deal_activity
  end

  # GET /deal_activities/new
  def new
    @deal_activity = DealActivity.new(deal_activity_params)
    @deal_activity.entity_id = @deal_activity.deal.entity_id
    authorize @deal_activity
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append('new_deal_activity', partial: "deal_activities/deal_form", locals: { deal_activity: @deal_activity })
        ]
      end
      format.html
    end
  end

  # GET /deal_activities/1/edit
  def edit
    # DealActivityEditOperation
    @deal_activity[:completed] = deal_activity_params[:completed] if params[:deal_activity].present?
  end

  # POST /deal_activities or /deal_activities.json
  def create
    @deal_activity = DealActivity.new(deal_activity_params)
    @deal_activity.entity_id = @deal_activity.deal.entity_id
    authorize @deal_activity

    @deal_activity.has_documents_nested_attributes = true if params[:deal_activity] && params[:deal_activity][:documents_attributes].present?

    setup_doc_user(@deal_activity)
    @current_user = current_user
    respond_to do |format|
      if @deal_activity.save
        @deal_activity.deal.kanban_board.broadcast_board_event if @deal_activity.deal.kanban_board.present?
        format.html do
          redirect_to deal_activity_url(@deal_activity), notice: "Deal activity was successfully created."
        end
        format.json { render :show, status: :created, location: @deal_activity }
        format.turbo_stream { render :create }
      else
        @alert = "Deal Investor could not be created!"
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal_activity.errors, status: :unprocessable_entity }
        @alert += " #{@deal_investor.errors.full_messages.join(', ')}"
        format.turbo_stream { render :create_failure, alert: @alert }
      end
    end
  end

  # PATCH/PUT /deal_activities/1 or /deal_activities/1.json
  def update
    setup_doc_user(@deal_activity)
    @deal_activity.has_documents_nested_attributes = true if params[:deal_activity] && params[:deal_activity][:documents_attributes].present?

    respond_to do |format|
      if @deal_activity.update(deal_activity_params)
        @deal_activity.deal.kanban_board.broadcast_board_event if @deal_activity.deal.kanban_board.present?
        format.html do
          redirect_url = params[:back_to].presence || deal_activity_url(@deal_activity)
          redirect_to redirect_url, notice: "Deal activity was successfully updated."
        end
        format.json { render :show, status: :ok, location: @deal_activity }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal_activity.errors, status: :unprocessable_entity }
      end
    end
  end

  def update_sequence
    ActiveRecord::Base.connected_to(role: :writing) do
      @deal_activity.set_list_position(params[:sequence].to_i + 1)
      @deal_activities = DealActivity.templates(@deal_activity.deal).includes(:deal).page params[:page]
      params[:template] = true
      @deal_activity.deal.kanban_board.broadcast_board_event if @deal_activity.deal.kanban_board.present?
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('deal_activities_frame', partial: "deal_activities/index", locals: { deal_activities: @deal_activities })
        ]
      end
      format.html { redirect_to deal_path(@deal_activity.deal, tab: "activities-tab"), notice: "Success! Deal activites will be recreated in a bit, please refresh the page in a minute." }
    end
  end

  def toggle_completed
    success = @deal_activity.update(deal_activity_params)

    respond_to do |format|
      if success
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(helpers.dom_id(@deal_activity.deal_investor), partial: "deals/grid_view_row",
                                                                               locals: { deal_investor: @deal_activity.deal_investor })
          ]
        end
        format.html { redirect_to deal_activity_url(@deal_activity), notice: "Activity was successfully updated." }
      else
        format.turbo_stream { redirect_to edit_deal_activity_path(@deal_activity, 'deal_activity[completed]': @deal_activity.completed), alert: @deal_activity.errors.full_messages }
        format.html { render :edit, back_to: deal_path(@deal_activity.deal) }
      end
    end
  end

  def perform_activity_action
    result = PerformActivityAction.call(params:,
                                        deal_activity: @deal_activity)
    if result.success?
      render json: {
        message: "Activity was successfully updated.",
        current_deal_activity_id: result[:deal_investor].current_deal_activity_id,
        severity_color: severity_color(result[:deal_investor])
      }, status: :ok
    else
      render json: { errors: result["errors"] }, status: :unprocessable_entity
    end
  end

  def update_sequences
    @deal_activities = policy_scope(DealActivity)
    result = UpdateSequences.call(params:)
    if result.success?
      render json: { success: true, message: "Sequences updated successfully" }
    else
      render json: { success: false, message: "Failed to update sequences" }, status: :unprocessable_entity
    end
  end

  # DELETE /deal_activities/1 or /deal_activities/1.json
  def destroy
    deal = @deal_activity.deal
    @deal_activity.destroy
    deal.kanban_board.broadcast_board_event if @deal_activity.deal.kanban_board.present?

    redirect_path = if @deal_activity.deal_investor_id.blank?
                      deal_activities_path(deal_id: @deal_activity.deal_id, template: true)
                    else
                      deal_activities_path(deal_id: @deal_activity.deal_id, deal_investor_id: @deal_activity.deal_investor_id)
                    end
    respond_to do |format|
      format.html { redirect_to redirect_path, notice: "Deal activity was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_deal_activity
    @deal_activity = DealActivity.find(params[:id])
    authorize @deal_activity
  end

  # Only allow a list of trusted parameters through.
  def deal_activity_params
    params.require(:deal_activity).permit(:deal_id, :deal_investor_id, :by_date, :status,
                                          :title, :details, :completed, :entity_id, :days,
                                          documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
