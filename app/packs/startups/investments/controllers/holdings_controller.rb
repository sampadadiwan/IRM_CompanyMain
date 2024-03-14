class HoldingsController < ApplicationController
  before_action :set_holding, only: %i[show edit update destroy cancel approve emp_ack]
  after_action :verify_authorized, except: %i[investor_calc employee_calc index search]

  # GET /holdings or /holdings.json
  def index
    authorize(Holding)
    @holdings = policy_scope(Holding).order(quantity: :desc)
    @holdings = @holdings.includes(:user, :entity, :investor, :funding_round)

    @secondary_sale = nil
    if params[:secondary_sale_id]
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
      @holdings = @holdings.where(entity_id: @secondary_sale.entity_id)
    end

    if params[:option_pool_id]
      @option_pool = OptionPool.find(params[:option_pool_id])
      @holdings = @holdings.where(option_pool_id: @option_pool.id)
    end

    filter(params)

    @holdings = @holdings.page params[:page] unless request.format.xlsx?

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=holdings.xlsx"
      end
      format.html { render :index }
      format.json { render :index }
    end
  end

  def filter(params)
    @holdings = @holdings.where(approved: params[:approved] == 'true') if params[:approved].present?
    @holdings = @holdings.where(manual_vesting: params[:manual_vesting] == 'true') if params[:manual_vesting].present?
    @holdings = @holdings.where("lapsed_quantity > 0") if params[:lapsed].present?
    @holdings = @holdings.where("gross_unvested_quantity > 0") if params[:unvested].present?
    @holdings = @holdings.where("net_avail_to_excercise_quantity > 0") if params[:avail_to_excercise].present?
    @holdings = @holdings.where("cancelled_quantity > 0") if params[:cancelled].present?
    @holdings = @holdings.where("excercised_quantity > 0") if params[:excercised].present?

    @holdings = @holdings.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @holdings = @holdings.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @holdings = @holdings.where(funding_round_id: params[:funding_round_id]) if params[:funding_round_id].present?
    @holdings = @holdings.where(holding_type: params[:holding_type]) if params[:holding_type].present?
    @holdings = @holdings.where(investment_instrument: params[:investment_instrument]) if params[:investment_instrument].present?
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @holdings = HoldingIndex.filter(term: { entity_id: @entity.id })
                              .query(query_string: { fields: HoldingIndex::SEARCH_FIELDS,
                                                     query:, default_operator: 'and' })

      @holdings = @holdings.page(params[:page]).objects

      render "index"
    else
      redirect_to :index
    end
  end

  # GET /holdings/1 or /holdings/1.json
  def show; end

  # GET /holdings/new
  def new
    @holding = Holding.new(holding_params)
    @holding.entity_id = current_user.entity_id
    @holding.holding_type = @holding.investor.category

    authorize @holding

    # Custom form fields
    setup_custom_fields(@holding)
  end

  # GET /holdings/1/edit
  def edit
    setup_custom_fields(@holding)
  end

  # POST /holdings or /holdings.json
  def create
    @holding = Holding.new(holding_params)
    authorize @holding

    respond_to do |format|
      if CreateHolding.wtf?(holding: @holding).success?
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to holding_url(@holding), notice: "Holding was successfully created." }
        format.json { render :show, status: :created, location: @holding }
      end
    end
  end

  # PATCH/PUT /holdings/1 or /holdings/1.json
  def update
    respond_to do |format|
      if @holding.update(holding_params)
        format.html { redirect_to holding_url(@holding), notice: "Holding was successfully updated." }
        format.json { render :show, status: :ok, location: @holding }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /holdings/1 or /holdings/1.json
  def destroy
    @holding.destroy

    respond_to do |format|
      format.html { redirect_to holdings_url, notice: "Holding was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def employee_calc
    @emp_calc = EmployeeCalc.new(calc_params, current_user)
    @quantity = calc_params[:quantity]
    @calc_total_value = calc_params[:total_value]
    @all_or_vested = calc_params[:all_or_vested]
    @holding_id = calc_params[:holding_id]
    @holdings = if @holding_id.present?
                  Holding.where(id: @holding_id)
                else
                  policy_scope(Holding)
                end
  end

  def investor_calc; end

  def cancel
    result = CancelHolding.wtf?(holding: @holding, all_or_unvested: params[:type])

    respond_to do |format|
      if result.success?
        format.html { redirect_to holding_url(@holding), notice: "Holding was successfully cancelled." }
        format.json { render :show, status: :created, location: @holding }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      end
    end
  end

  def emp_ack
    @holding.emp_ack = true
    @holding.emp_ack_date = Time.zone.now
    respond_to do |format|
      if @holding.save
        format.html { redirect_to holding_url(@holding), notice: "Holding was successfully acknowledged." }
        format.json { render :show, status: :created, location: @holding }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      end
    end
  end

  def approve
    result = ApproveHolding.wtf?(holding: @holding)
    respond_to do |format|
      if result.success?
        format.html { redirect_to holding_url(@holding), notice: "Holding was successfully approved." }
        format.json { render :show, status: :created, location: @holding }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      end
    end
  end

  def approve_all_holdings
    @parent = if params[:option_pool_id].present?
                OptionPool.find(params[:option_pool_id])
              elsif params[:funding_round_id].present?
                FundingRound.find(params[:funding_round_id])
              else
                current_user.entity
              end
    authorize @parent

    respond_to do |format|
      if @parent
        HoldingApproveJob.perform_later(@parent.class.name, @parent.id)
        if @parent == current_user.entity
          format.html { redirect_to holdings_path, notice: "Holdings will be approved shortly. Please checkback in a minute." }
        else
          format.html { redirect_to @parent, notice: "Holdings will be approved shortly. Please checkback in a minute." }
        end
        format.json { render :show, status: :ok, location: @holding }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @holding.errors, status: :unprocessable_entity }
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_holding
    @holding = Holding.find(params[:id])
    authorize @holding
  end

  # Only allow a list of trusted parameters through.
  def holding_params
    params.require(:holding).permit(:user_id, :investor_id, :entity_id, :orig_grant_quantity, :price,
                                    :value, :investment_instrument, :holding_type, :funding_round_id, :note, :form_type_id, :option_pool_id, :grant_date, :employee_id, :manual_vesting, :preferred_conversion, :vested_quantity, :department, :option_type,
                                    :grant_letter, properties: {})
  end

  def calc_params
    quantity = params[:quantity_hidden]
    all_or_vested = params[:all_or_vested_hidden]
    total_value = params[:calc_total_value_hidden]
    price_growth = params[:price_growth]
    tax_rate = params[:tax_rate]
    holding_id = params[:holding_id]
    { quantity:, price_growth:, tax_rate:, all_or_vested:, total_value:, holding_id: }
  end
end
