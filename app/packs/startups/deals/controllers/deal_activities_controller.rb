class DealActivitiesController < ApplicationController
  before_action :set_deal_activity, only: %w[show update destroy edit update_sequence toggle_completed]
  skip_before_action :verify_authenticity_token, only: [:update_sequence], raise: false

  # GET /deal_activities or /deal_activities.json
  def index
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
    @deal_activity.entity_id = current_user.entity_id
    authorize @deal_activity
  end

  # GET /deal_activities/1/edit
  def edit
    @deal_activity[:completed] = deal_activity_params[:completed] if params[:deal_activity].present?
  end

  # POST /deal_activities or /deal_activities.json
  def create
    @deal_activity = DealActivity.new(deal_activity_params)
    @deal_activity.entity_id = current_user.entity_id
    authorize @deal_activity

    @deal_activity.has_documents_nested_attributes = true if params[:deal_activity] && params[:deal_activity][:documents_attributes].present?

    setup_doc_user(@deal_activity)

    respond_to do |format|
      if @deal_activity.save
        format.html do
          redirect_url = params[:back_to].presence || deal_activity_url(@deal_activity)
          redirect_to redirect_url, notice: "Deal activity was successfully created."
        end
        format.json { render :show, status: :created, location: @deal_activity }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal_activity.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /deal_activities/1 or /deal_activities/1.json
  def update
    setup_doc_user(@deal_activity)
    @deal_activity.has_documents_nested_attributes = true if params[:deal_activity] && params[:deal_activity][:documents_attributes].present?

    respond_to do |format|
      if @deal_activity.update(deal_activity_params)
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
    DealActivity.public_activity_off
    @deal_activity.set_list_position(params[:sequence].to_i + 1)
    DealActivity.public_activity_on

    # @deal_activity.create_activity key: 'deal_activity.sequence.updated', owner: current_user
    @deal_activities = DealActivity.templates(@deal_activity.deal).includes(:deal).page params[:page]
    params[:template] = true

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
    DealActivity.public_activity_off
    success = @deal_activity.update(deal_activity_params)
    DealActivity.public_activity_on

    @deal_activity.create_activity key: 'deal_activity.completed', owner: current_user if @deal_activity.completed

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
        format.html { render :edit }
      end
    end
  end

  # DELETE /deal_activities/1 or /deal_activities/1.json
  def destroy
    @deal_activity.destroy

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
