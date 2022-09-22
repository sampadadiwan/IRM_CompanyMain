class DealsController < ApplicationController
  before_action :set_deal, only: %w[show update destroy edit start_deal recreate_activities]
  after_action :verify_authorized, except: %i[index search investor_deals]

  # GET /deals or /deals.json
  def index
    @deals = policy_scope(Deal)

    @deals = if params[:other_deals].present?
               Deal.deals_for_vc(current_user)
             else
               @deals # .includes(:entity)
             end

    @deals = @deals.where("deals.archived=?", false) if params[:include_archived].blank?

    # @deals = @deals.page params[:page]
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

  def recreate_activities
    GenerateDealActivitiesJob.perform_later(@deal.id, "Deal")
    respond_to do |format|
      format.html { redirect_to deal_url(@deal), notice: "Success! Deal activites will be recreated in a bit, please be patient." }
    end
  end

  # GET /deals/1 or /deals/1.json
  def show
    # @deal_investors = @deal.deal_investors.order("deal_investors.primary_amount_cents desc")
    # @deal_investors = @deal_investors.not_declined if params[:all].blank?

    if params[:grid_view] == "false" || @deal.start_date.nil?
      render "show"
    elsif params[:chart].present?
      render "deal_charts"
    else
      respond_to do |format|
        format.xlsx do
          @activity_names = %w[Investor Status Primary Secondary] + DealActivity.templates(@deal)
          response.headers[
            'Content-Disposition'
          ] = "attachment; filename=deal.xlsx"

          render "grid_view"
        end
        format.html { render "grid_view" }
      end
    end
  end

  # GET /deals/new
  def new
    @deal = Deal.new(deal_params)
    @deal.currency = @deal.entity.currency
    @deal.activity_list = Deal::ACTIVITIES

    authorize @deal
    setup_custom_fields(@deal)
  end

  # GET /deals/1/edit
  def edit
    setup_custom_fields(@deal)
  end

  def start_deal
    @deal.start_deal

    respond_to do |format|
      format.turbo_stream { render :start_deal }
      format.html { redirect_to deal_url(@deal), notice: "Deal was successfully started." }
    end
  end

  # POST /deals or /deals.json
  def create
    @deal = Deal.new(deal_params)
    @deal.entity_id = current_user.entity_id
    authorize @deal

    @deal = CreateDeal.call(deal: @deal).deal
    respond_to do |format|
      if @deal.errors.any?
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to deal_url(@deal), notice: "Deal was successfully created." }
        format.json { render :show, status: :created, location: @deal }
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
    authorize(@deal)
  end

  # Only allow a list of trusted parameters through.
  def deal_params
    params.require(:deal).permit(:entity_id, :name, :amount, :status, :form_type_id,
                                 :currency, :units, :activity_list, :archived, properties: {})
  end
end
