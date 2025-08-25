class InvestmentInstrumentsController < ApplicationController
  before_action :set_investment_instrument, only: %i[show edit update destroy]
  skip_after_action :verify_authorized, only: %i[sub_categories]

  # GET /investment_instruments or /investment_instruments.json
  def index
    # Step 1: Base scope with policy and eager loading
    @investment_instruments = policy_scope(InvestmentInstrument).includes(:portfolio_company)

    # Step 2: Apply filters if corresponding params are present
    @investment_instruments = filter_params(
      @investment_instruments,
      :portfolio_company_id,
      :category,
      :sub_category,
      :sector,
      :import_upload_id
    )

    @investment_type = params[:investment_type] || :portfolio_investment
  end

  # GET /investment_instruments/1 or /investment_instruments/1.json
  def show; end

  # GET /investment_instruments/new
  def new
    @investment_instrument = InvestmentInstrument.new(investment_instrument_params)
    @investment_instrument.entity_id = current_user.entity_id
    authorize @investment_instrument
    # form_type is assigned to a new investment instrument object - by deafult the last one. but if it is passed in the params we need to force it
    # as using the last one can cause issues if a user has selected a different form type which was not the last one
    setup_custom_fields(@investment_instrument, force_form_type: @investment_instrument.form_type)
  end

  # GET /investment_instruments/1/edit
  def edit
    setup_custom_fields(@investment_instrument)
  end

  # POST /investment_instruments or /investment_instruments.json
  def create
    @investment_instrument = InvestmentInstrument.new(investment_instrument_params)
    authorize @investment_instrument
    respond_to do |format|
      if @investment_instrument.save
        url = params[:back_to].presence || investment_instrument_url(@investment_instrument)
        format.html { redirect_to url, notice: "Investment instrument was successfully created." }
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

  def sub_categories
    @sub_categories = InvestmentInstrument::CATEGORIES[params[:category]]
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
    params.require(:investment_instrument).permit(:name, :category, :sub_category, :sector, :entity_id, :portfolio_company_id, :investment_domicile, :deleted_at, :form_type_id, :currency, properties: {})
  end
end
