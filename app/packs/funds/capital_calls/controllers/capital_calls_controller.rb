class CapitalCallsController < ApplicationController
  before_action :set_capital_call, only: %i[show edit update destroy reminder approve generate_docs allocate_units]

  # GET /capital_calls or /capital_calls.json
  def index
    @capital_calls = policy_scope(CapitalCall).includes(:fund)
    @capital_calls = @capital_calls.where(fund_id: params[:fund_id]) if params[:fund_id]

    respond_to do |format|
      format.xlsx
      format.html { render :index }
      format.json { render json: CapitalCallDatatable.new(params, capital_calls: @capital_calls) }
    end
  end

  # GET /capital_calls/1 or /capital_calls/1.json
  def show; end

  def generate_docs
    CapitalCallRemittanceDocJob.perform_later(@capital_call.id, current_user.id)
    redirect_to capital_call_path(@capital_call), notice: "Documentation generation started, please check back in a few mins. Each remittance will have the customized document attached"
  end

  def allocate_units
    FundUnitsJob.perform_later(@capital_call.id, "CapitalCall", @capital_call.name, current_user.id)
    redirect_to capital_call_path(@capital_call), notice: "Allocation process started, please check back in a few mins."
  end

  # GET /capital_calls/new
  def new
    @capital_call = CapitalCall.new(capital_call_params)
    @capital_call.entity_id = @capital_call.fund.entity_id
    @capital_call.due_date = Time.zone.today + 2.weeks
    @capital_call.call_date = Time.zone.today
    authorize @capital_call
    setup_custom_fields(@capital_call)
  end

  # GET /capital_calls/1/edit
  def edit
    setup_custom_fields(@capital_call)
  end

  # POST /capital_calls or /capital_calls.json
  def create
    @capital_call = CapitalCall.new(capital_call_params)
    authorize @capital_call

    respond_to do |format|
      if @capital_call.save
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was successfully created." }
        format.json { render :show, status: :created, location: @capital_call }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_calls/1 or /capital_calls/1.json
  def update
    respond_to do |format|
      if @capital_call.update(capital_call_params)
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_call }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_calls/1 or /capital_calls/1.json
  def destroy
    @capital_call.destroy

    respond_to do |format|
      format.html { redirect_to fund_url(id: @capital_call.fund_id, tab: "capital-calls-tab"), notice: "Capital call was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def approve
    @capital_call.approved = true
    @capital_call.approved_by_user = current_user

    respond_to do |format|
      if @capital_call.save
        format.html { redirect_to capital_call_url(@capital_call), notice: "Capital call was successfully approved." }
        format.json { render :show, status: :created, location: @capital_call }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_call.errors, status: :unprocessable_entity }
      end
    end
  end

  def reminder
    @capital_call.reminder_capital_call
    redirect_to capital_call_url(@capital_call), notice: "Reminder sent for capital call."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_call
    @capital_call = CapitalCall.find(params[:id])
    authorize @capital_call
    @bread_crumbs = { Funds: funds_path, "#{@capital_call.fund.name}": fund_path(@capital_call.fund),
                      "#{@capital_call}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_call_params
    params.require(:capital_call).permit(:entity_id, :fund_id, :form_type_id, :name, :percentage_called, :add_fees, :generate_remittances, :due_date, :call_date, :notes, :commitment_type, :call_basis, :amount_to_be_called, fund_closes: [], unit_prices: {}, properties: {}, call_fees_attributes: CallFee::NESTED_ATTRIBUTES)
  end
end
