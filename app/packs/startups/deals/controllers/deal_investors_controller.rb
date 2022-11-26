class DealInvestorsController < ApplicationController
  before_action :set_deal_investor, only: %w[show update destroy edit]
  after_action :verify_policy_scoped, only: %i[]

  # GET /deal_investors or /deal_investors.json
  def index
    @deal_investors = if params[:for_investor].present?
                        DealInvestor.for_investor(current_user)
                      else
                        policy_scope(DealInvestor).includes(:investor, :deal)
                      end
    @deal_investors = @deal_investors.where(deal_id: params[:deal_id]) if params[:deal_id].present?
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

  # GET /deal_investors/1 or /deal_investors/1.json
  def show
    authorize @deal_investor
  end

  # GET /deal_investors/new
  def new
    @deal_investor = DealInvestor.new(deal_investor_params)
    authorize @deal_investor
  end

  # GET /deal_investors/1/edit
  def edit
    authorize @deal_investor
  end

  # POST /deal_investors or /deal_investors.json
  def create
    @deal_investor = DealInvestor.new(deal_investor_params)
    @deal_investor.entity_id = current_user.entity_id
    # This is required after the money gem was installed
    @deal_investor.primary_amount = deal_investor_params[:primary_amount].to_d
    @deal_investor.secondary_investment = deal_investor_params[:secondary_investment].to_d
    @deal_investor.pre_money_valuation = deal_investor_params[:pre_money_valuation].to_d

    authorize @deal_investor.deal
    authorize @deal_investor

    respond_to do |format|
      if @deal_investor.save
        format.html { redirect_to deal_investor_url(@deal_investor), notice: "Deal investor was successfully created." }
        format.json { render :show, status: :created, location: @deal_investor }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal_investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /deal_investors/1 or /deal_investors/1.json
  def update
    authorize @deal_investor

    respond_to do |format|
      if @deal_investor.update(deal_investor_params)
        format.html { redirect_to deal_investor_url(@deal_investor), notice: "Deal investor was successfully updated." }
        format.json { render :show, status: :ok, location: @deal_investor }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal_investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /deal_investors/1 or /deal_investors/1.json
  def destroy
    authorize @deal_investor
    @deal_investor.destroy

    respond_to do |format|
      format.html { redirect_to deal_investors_url, notice: "Deal investor was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_deal_investor
    @deal_investor = DealInvestor.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def deal_investor_params
    params.require(:deal_investor).permit(:deal_id, :investor_id, :status, :primary_amount, :notes,
                                          :secondary_investment, :entity_id, :investor_advisor, :company_advisor, :pre_money_valuation, :tier)
  end
end
