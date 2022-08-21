class CapitalRemittancesController < ApplicationController
  before_action :set_capital_remittance, only: %i[show edit update destroy]

  # GET /capital_remittances or /capital_remittances.json
  def index
    @capital_remittances = policy_scope(CapitalRemittance).includes(:fund, :investor, :capital_call)
    @capital_remittances = @capital_remittances.where(fund_id: params[:fund_id]) if params[:fund_id]
    @capital_remittances = @capital_remittances.where(capital_call_id: params[:capital_call_id]) if params[:capital_call_id]
  end

  # GET /capital_remittances/1 or /capital_remittances/1.json
  def show; end

  # GET /capital_remittances/new
  def new
    @capital_remittance = CapitalRemittance.new(capital_remittance_params)
    @capital_remittance.entity_id = @capital_remittance.capital_call.entity_id
    @capital_remittance.fund_id = @capital_remittance.capital_call.fund_id

    @capital_remittance.call_amount = @capital_remittance.due_amount
    authorize @capital_remittance
  end

  # GET /capital_remittances/1/edit
  def edit; end

  # POST /capital_remittances or /capital_remittances.json
  def create
    @capital_remittance = CapitalRemittance.new(capital_remittance_params)
    authorize @capital_remittance
    respond_to do |format|
      if @capital_remittance.save
        format.html { redirect_to capital_remittance_url(@capital_remittance), notice: "Capital remittance was successfully created." }
        format.json { render :show, status: :created, location: @capital_remittance }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_remittance.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_remittances/1 or /capital_remittances/1.json
  def update
    respond_to do |format|
      if @capital_remittance.update(capital_remittance_params)
        format.html { redirect_to capital_remittance_url(@capital_remittance), notice: "Capital remittance was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_remittance }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_remittance.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_remittances/1 or /capital_remittances/1.json
  def destroy
    @capital_remittance.destroy

    respond_to do |format|
      format.html { redirect_to capital_remittances_url, notice: "Capital remittance was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_remittance
    @capital_remittance = CapitalRemittance.find(params[:id])
    authorize @capital_remittance
  end

  # Only allow a list of trusted parameters through.
  def capital_remittance_params
    params.require(:capital_remittance).permit(:entity_id, :fund_id, :capital_call_id, :investor_id, :status, :call_amount, :collected_amount, :notes)
  end
end
