class DealInvestorsController < ApplicationController
  before_action :set_deal_investor, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[kanban_search index]
  # GET /deal_investors or /deal_investors.json
  def index
    @q = DealInvestor.ransack(params[:q])
    @deal_investors = policy_scope(@q.result).includes(:investor, :deal)

    @deal_investors = @deal_investors.where(deal_id: params[:deal_id]) if params[:deal_id].present?
    @deal_investors = @deal_investors.where(entity_id: params[:entity_id]) if params[:entity_id].present?

    if params[:turbo] && params[:boards] && params[:board_id].present?
      @kanban_cards = KanbanCard.where(data_source_type: "DealInvestor", data_source_id: @deal_investors.pluck(:id))
      @filtered_results = false
      kanban_board = KanbanBoard.find(params["board_id"])
      render turbo_stream: [
        turbo_stream.replace("board_#{kanban_board.id}", partial: "/boards/kanban", locals: { kanban_cards: @kanban_cards, kanban_board:, filtered_results: @filtered_results })
      ]
    end
  end

  def search
    @entity = current_user.entity
    # investor_or_investee = "*, IF(investor_entity_id = #{current_user.entity_id} OR entity_id = #{current_user.entity_id}, 1, 0) AS inv"

    query = params[:query]
    if query.present?
      @deal_investors = DealInvestorIndex.filter(term: { entity_id: @entity.id })
                                         .query(query_string: { fields: DealInvestorIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to deal_investors_path
    end
  end

  def kanban_search
    @entity = current_user.entity
    @q = DealInvestor.ransack(params[:q])
    # @deal_investors = policy_scope(@q.result).includes(:investor, :deal)
    @deal_investors = if params[:query].blank?
                        @entity.deal_investors
                        # @deal_investors
                      else
                        deal_investor_ids = DealInvestorIndex.filter(term: { entity_id: @entity.id })
                                                             .query(query_string: { fields: DealInvestorIndex::SEARCH_FIELDS,
                                                                                    query: "*#{params[:query]}*", default_operator: 'and' }).objects.pluck(:id)
                        DealInvestor.where(id: deal_investor_ids) # @deal_investors.where
                      end

    @deal = params[:deal].present? ? Deal.find(params[:deal]) : @deal_investors.first.deal

    render turbo_stream: [
      turbo_stream.replace("kanban_#{@deal.id}", partial: "/deals/kanban", locals: { deal_investors: @deal_investors, deal_activities: DealActivity.templates(@deal) })
    ]
  end

  # GET /deal_investors/1 or /deal_investors/1.json
  def show
    authorize @deal_investor

    respond_to do |format|
      format.turbo_stream do
        frame = params[:turbo_frame] || "deal_investor_show_#{params[:id]}"
        render turbo_stream: [
          turbo_stream.replace(frame, partial: "deal_investors/deal_show", locals: { deal_investor: @deal_investor, update_allowed: policy(@deal_investor).update?, belongs_to_entity: current_user.entity_id == @deal_investor.entity_id, turbo_tag: frame })
        ]
      end
      format.html
    end
  end

  # GET /deal_investors/new
  def new
    @deal_investor = DealInvestor.new(deal_investor_params)
    authorize @deal_investor
    setup_custom_fields(@deal_investor)

    frame = params[:turbo_frame] || "new_deal_investor"
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(frame, partial: "deal_investors/deal_form", locals: { deal_investor: @deal_investor, turbo_tag: frame })
        ]
      end
      format.html
    end
  end

  # GET /deal_investors/1/edit
  def edit
    authorize @deal_investor
    setup_custom_fields(@deal_investor)
    @kanban_card = KanbanCard.find_by(data_source_id: @deal_investor.id, data_source_type: @deal_investor.class.name)
    @kanban_column = @kanban_card&.kanban_column

    respond_to do |format|
      format.turbo_stream do
        frame = params[:turbo_frame] || "deal_investor_show_#{params[:id]}"
        render turbo_stream: [
          turbo_stream.replace(frame, partial: "deal_investors/offcanvas_form", locals: { deal_investor: @deal_investor, belongs_to_entity: current_user.entity_id == @deal_investor.entity_id, update_allowed: DealInvestorPolicy.new(current_user, @deal_investor).update?, turbo_tag: frame, doc_owner_tag: @kanban_column&.name })
        ]
      end
      format.html
    end
  end

  # POST /deal_investors or /deal_investors.json
  def create
    @deal_investor = DealInvestor.new(deal_investor_params)
    @deal_investor.entity_id = @deal_investor.deal.entity_id
    # This is required after the money gem was installed
    @deal_investor.primary_amount = deal_investor_params[:primary_amount].to_d
    @deal_investor.secondary_investment = deal_investor_params[:secondary_investment].to_d
    @deal_investor.pre_money_valuation = deal_investor_params[:pre_money_valuation].to_d

    authorize @deal_investor.deal
    authorize @deal_investor

    setup_doc_user(@deal_investor)

    @current_user = current_user
    @frame = params[:turbo_frame] || params[:deal_investor][:turbo_frame] || "new_deal_investor"

    respond_to do |format|
      if DealInvestorCreate.call(deal_investor: @deal_investor).success?
        format.html { redirect_to deal_investor_url(@deal_investor), notice: "Deal investor was successfully created." }
        format.json { render :show, status: :created, location: @deal_investor }
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Deal Investor was successfully created!", level: "success").broadcast
          render :create
        end
      else
        @alert = "Deal Investor could not be created!"
        format.html do
          render :new, status: :unprocessable_entity
        end
        format.json { render json: @deal_investor.errors, status: :unprocessable_entity }
        @alert += " #{@deal_investor.errors.full_messages.join(', ')}"
        format.turbo_stream { render :create_failure, alert: @alert }
      end
    end
  end

  # PATCH/PUT /deal_investors/1 or /deal_investors/1.json
  def update
    authorize @deal_investor
    setup_doc_user(@deal_investor)
    @deal_investor.assign_attributes(deal_investor_params)
    @current_user = current_user
    @frame = params[:deal_investor][:turbo_frame] || "deal_investor_form_offcanvas#{@deal_investor.id}"
    @result = DealInvestorUpdate.call(deal_investor: @deal_investor)
    respond_to do |format|
      if @result.success?
        @message = "Deal investor was successfully updated."
        @deal_investor.deal.broadcast_message(@message)
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(@frame, partial: "deal_investors/deal_show", locals: {
                                                      deal_investor: @deal_investor,
                                                      update_allowed: policy(@deal_investor).update?,
                                                      turbo_tag: @frame,
                                                      belongs_to_entity: current_user.entity_id == @deal_investor.entity_id
                                                    })
        end
        format.html { redirect_to deal_investor_url(@deal_investor), notice: "Deal investor was successfully updated." }
        format.json { render :show, status: :ok, location: @deal_investor }
      else
        @deal_investor.deal.broadcast_message("Failed to update Deal Investor #{@deal_investor&.investor_name}")
        format.turbo_stream do
          turbo_stream.replace(@frame, partial: "deal_investors/offcanvas_form", locals: { deal_investor: @deal_investor, current_user: @current_user, turbo_tag: @frame })
        end
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal_investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /deal_investors/1 or /deal_investors/1.json
  def destroy
    authorize @deal_investor
    DealInvestorDestroy.call(deal_investor: @deal_investor)

    respond_to do |format|
      @message = "Deal investor was successfully destroyed."
      @status = "success"
      format.turbo_stream do
        UserAlert.new(user_id: current_user.id, message: @message, level: "info").broadcast
      end
      format.html { redirect_to deal_investors_url, notice: @message }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_deal_investor
    @deal_investor = DealInvestor.find(params[:id])
    @bread_crumbs = { Deals: deals_path, "#{@deal_investor.deal.name || '-'}": deal_path(@deal_investor.deal), "#{@deal_investor.investor_name || '-'}": deal_investor_path(@deal_investor) }
  end

  # Only allow a list of trusted parameters through.
  def deal_investor_params
    params.require(:deal_investor).permit(:deal_id, :investor_id, :status, :primary_amount, :notes, :tags, :source, :deal_lead,
                                          :secondary_investment, :entity_id, :investor_advisor, :company_advisor, :pre_money_valuation, :tier, :fee, :deal_activity_id, :kanban_column_id, :form_type_id, properties: {}, documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
