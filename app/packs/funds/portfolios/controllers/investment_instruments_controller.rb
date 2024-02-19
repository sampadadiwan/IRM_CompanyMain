class InvestmentInstrumentsController < ApplicationController
  before_action :set_investment_instrument, only: %i[show edit update destroy]

  # GET /investment_instruments or /investment_instruments.json
  def index
    @investment_instruments = policy_scope(InvestmentInstrument)
  end

  # GET /investment_instruments/1 or /investment_instruments/1.json
  def show; end

  # GET /investment_instruments/new
  def new
    @investment_instrument = InvestmentInstrument.new(investment_instrument_params)
    authorize @investment_instrument
  end

  # GET /investment_instruments/1/edit
  def edit; end

  # POST /investment_instruments or /investment_instruments.json
  def create
    @investment_instrument = InvestmentInstrument.new(investment_instrument_params)
    authorize @investment_instrument
    respond_to do |format|
      if @investment_instrument.save
        format.html { redirect_to investment_instrument_url(@investment_instrument), notice: "Investment instrument was successfully created." }
        format.json { render :show, status: :created, location: @investment_instrument }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investment_instrument.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investment_instruments/1 or /investment_instruments/1.json
  def update
    respond_to do |format|
      if @investment_instrument.update(investment_instrument_params)
        format.html { redirect_to investment_instrument_url(@investment_instrument), notice: "Investment instrument was successfully updated." }
        format.json { render :show, status: :ok, location: @investment_instrument }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investment_instrument.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investment_instruments/1 or /investment_instruments/1.json
  def destroy
    @investment_instrument.destroy!

    respond_to do |format|
      format.html { redirect_to investment_instruments_url, notice: "Investment instrument was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment_instrument
    @investment_instrument = InvestmentInstrument.find(params[:id])
    authorize @investment_instrument
  end

  # Only allow a list of trusted parameters through.
  def investment_instrument_params
    params.require(:investment_instrument).permit(:name, :category, :sub_category, :sector, :entity_id, :portfolio_company_id, :deleted_at)
  end
end
