class ExchangeRatesController < ApplicationController
  before_action :set_exchange_rate, only: %i[show edit update destroy generate_tracking_numbers]

  # GET /exchange_rates or /exchange_rates.json
  def index
    @exchange_rates = policy_scope(ExchangeRate)
    @exchange_rates = @exchange_rates.latest if params[:all].blank?
  end

  def generate_tracking_numbers
    TrackingCurrencyJob.perform_later(entity_id: @exchange_rate.entity_id, user_id: current_user.id)
    redirect_to exchange_rate_path(@exchange_rate), notice: "Tracking currency update started, please check back in a few mins."
  end

  # GET /exchange_rates/1 or /exchange_rates/1.json
  def show; end

  # GET /exchange_rates/new
  def new
    @exchange_rate = ExchangeRate.new
    @exchange_rate.entity_id = current_user.entity_id
    @exchange_rate.as_of = Time.zone.today
    @exchange_rate.to = params[:to]
    @exchange_rate.from = params[:from]

    authorize @exchange_rate
  end

  # GET /exchange_rates/1/edit
  def edit; end

  # POST /exchange_rates or /exchange_rates.json
  def create
    @exchange_rate = ExchangeRate.new(exchange_rate_params)
    authorize @exchange_rate
    respond_to do |format|
      if @exchange_rate.save
        format.html { redirect_to exchange_rate_url(@exchange_rate), notice: "Exchange rate was successfully created." }
        format.json { render :show, status: :created, location: @exchange_rate }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @exchange_rate.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /exchange_rates/1 or /exchange_rates/1.json
  def update
    respond_to do |format|
      if @exchange_rate.update(exchange_rate_params)
        format.html { redirect_to exchange_rate_url(@exchange_rate), notice: "Exchange rate was successfully updated." }
        format.json { render :show, status: :ok, location: @exchange_rate }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @exchange_rate.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /exchange_rates/1 or /exchange_rates/1.json
  def destroy
    respond_to do |format|
      if @exchange_rate.destroy
        format.html { redirect_to exchange_rates_url, notice: "Exchange rate was successfully destroyed." }
        format.json { head :no_content }
      else
        # This branch is for validation/callback failures, not FK errors
        format.html { redirect_to exchange_rate_url(@exchange_rate), alert: @exchange_rate.errors.full_messages.to_sentence }
        format.json { render json: @exchange_rate.errors, status: :unprocessable_entity }
      end
    end
  rescue ActiveRecord::InvalidForeignKey
    respond_to do |format|
      format.html do
        redirect_to exchange_rate_url(@exchange_rate),
                    alert: "This exchange rate cannot be deleted because it is used in other records."
      end

      format.json do
        render json: { error: "This exchange rate cannot be deleted because it is used in other records." },
               status: :unprocessable_entity
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_exchange_rate
    @exchange_rate = ExchangeRate.find(params[:id])
    authorize @exchange_rate
    @bread_crumbs = { 'Exchange Rates': exchange_rates_path, "#{@exchange_rate}": exchange_rate_path(@exchange_rate) }
  end

  # Only allow a list of trusted parameters through.
  def exchange_rate_params
    params.require(:exchange_rate).permit(:entity_id, :from, :to, :rate, :as_of, :notes)
  end
end
