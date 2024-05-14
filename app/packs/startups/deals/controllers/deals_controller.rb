class DealsController < ApplicationController
  before_action :set_deal, only: %w[show update destroy edit kanban]
  after_action :verify_authorized, except: %i[index search investor_deals]

  # GET /deals or /deals.json
  def index
    @deals = policy_scope(Deal)
    @bread_crumbs = { Deals: deals_path }
    @deals = @deals.where("deals.archived=?", false) if params[:include_archived].blank?
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @deals = DealIndex.filter(term: { entity_id: @entity.id })
                        .query(query_string: { fields: DealIndex::SEARCH_FIELDS,
                                               query:, default_operator: 'and' }).objects
    else
      redirect_to deals_path
    end

    render "index"
  end

  def investor_deals
    @deals = Deal.for_investor(current_user)
    @deals = @deals.page params[:page]
    render "index"
  end

  # GET /deals/1 or /deals/1.json
  def show
    if params[:chart].present?
      render "deal_charts"
    else
      respond_to do |format|
        format.xlsx do
          @activity_names = %w[Investor Status Primary Secondary Advisor] + DealActivity.templates(@deal)
          response.headers[
            'Content-Disposition'
          ] = "attachment; filename=deal.xlsx"

          render params[:kanban].present? ? "show" : "grid_view"
        end
        format.html { render "grid_view" }
      end
    end
  end

  def kanban
    @deal_investor = DealInvestor.new(deal: @deal, entity: @deal.entity)
    @deal_activity = DealActivity.new(deal: @deal, entity: @deal.entity)
    @q = @deal.deal_investors.ransack(params[:q])
    @deal_investors = policy_scope(@q.result)
    params[:kanban] = true
    render "deals/show"
  end

  # GET /deals/new
  def new
    @deal = Deal.new(deal_params)
    @deal.currency = @deal.entity.currency
    @deal.activity_list = Deal::ACTIVITIES
    @deal.start_date = Time.zone.today

    authorize @deal
    setup_custom_fields(@deal)
  end

  # GET /deals/1/edit
  def edit
    setup_custom_fields(@deal)
  end

  # POST /deals or /deals.json
  def create
    @deal = Deal.new(deal_params)
    @deal.entity_id = current_user.entity_id
    authorize @deal

    results = CreateDeal.wtf?(deal: @deal)
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
    respond_to do |format|
      if @deal.update(deal_params)
        format.html { redirect_to deal_url(@deal), notice: "Deal was successfully updated." }
        format.json { render :show, status: :ok, location: @deal }
      else
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

  # Use callbacks to share common setup or constraints between actions.
  def set_deal
    @deal = Deal.find(params[:id])
    @bread_crumbs = { Deals: deals_path, "#{@deal.name || '-'}": deal_path(@deal) }
    authorize(@deal)
  end

  # Only allow a list of trusted parameters through.
  def deal_params
    params.require(:deal).permit(:entity_id, :name, :amount, :status, :form_type_id, :clone_from_id,
                                 :start_date, :currency, :units, :activity_list, :archived, properties: {})
  end
end
