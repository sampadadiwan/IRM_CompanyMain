class InvestmentsController < ApplicationController
  include InvestmentConcern

  before_action :set_investment, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[index search investor_investments]

  # GET /investments or /investments.json
  def index
    @entity = current_user.entity

    @investments = policy_scope(Investment).includes(:investor, :funding_round)

    @investments = @investments.where(investor_id: params[:investor_id]) if params[:investor_id]
    @investments = @investments.where(funding_round_id: params[:funding_round_id]) if params[:funding_round_id]
    @investments = @investments.where(investment_instrument: Investment::EQUITY_LIKE) if params[:equity_like]

    @investments = @investments.order(id: :asc)

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=investments.xlsx"
      end
      format.html { render :index }
      format.json { render :index }
      format.pdf do
        render template: "investments/index", formats: [:html], pdf: "#{@entity.name} Investments"
      end
    end
  end

  def investor_investments
    if params[:entity_id].present?
      @entity = Entity.find(params[:entity_id])
      @investments = Investment.for_investor(current_user, @entity)
    end

    @investments = @investments.order(initial_value: :desc)
                               .includes(:entity, investor: :investor_entity).distinct

    render "index"
  end

  def search
    @entity = current_user.entity

    query = params[:query]
    if query.present?
      @investments = if current_user.has_role?(:super)

                       InvestmentIndex.query(query_string: { fields: InvestmentIndex::SEARCH_FIELDS,
                                                             query:, default_operator: 'and' }).objects

                     else
                       InvestmentIndex.filter(term: { entity_id: current_user.entity_id })
                                      .query(query_string: { fields: InvestmentIndex::SEARCH_FIELDS,
                                                             query:, default_operator: 'and' }).objects
                     end

    end

    render "search"
  end

  # GET /investments/1 or /investments/1.json
  def show
    authorize @investment
    respond_to do |format|
      format.html
      format.pdf do
        render template: "investments/show", formats: [:html], pdf: "Investment #{@investment.id}"
      end
    end
  end

  # GET /investments/new
  def new
    @investment = Investment.new(investment_params)
    authorize @investment
  end

  # GET /investments/1/edit
  def edit
    authorize @investment
  end

  # POST /investments or /investments.json
  def create
    investments = new_multi_investments(params, investment_params)

    saved_count = 0
    Investment.transaction do
      investments.each do |i|
        inv = SaveInvestment.call(investment: i).investment
        saved_count += 1 unless inv.errors.any?
      end
    end

    respond_to do |format|
      if investments.length.positive? && saved_count == investments.length
        format.html { redirect_to investments_path, notice: "Investment was successfully created." }
        format.json { render :show, status: :created, location: @investment }
      else
        format.html { render :new, status: :unprocessable_entity, notice: "Some investments were not created. Please try again." }
        format.json { render json: @investment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investments/1 or /investments/1.json
  def update
    authorize @investment
    @investment.assign_attributes(investment_params)
    @investment = SaveInvestment.call(investment: @investment).investment

    respond_to do |format|
      if @investment.errors.any?
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investment.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to investment_url(@investment), notice: "Investment was successfully updated." }
        format.json { render :show, status: :ok, location: @investment }
      end
    end
  end

  # DELETE /investments/1 or /investments/1.json
  def destroy
    authorize @investment
    @investment.destroy

    respond_to do |format|
      format.html { redirect_to investments_url, notice: "Investment was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment
    @investment = Investment.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def investment_params
    params.require(:investment).permit(:funding_round_id, :investor_id, :price, :notes,
                                       :entity_id, :investor_type, :investment_instrument, :quantity,
                                       :category, :initial_value, :current_value, :spv,
                                       :status, :liquidation_preference)
  end
end
