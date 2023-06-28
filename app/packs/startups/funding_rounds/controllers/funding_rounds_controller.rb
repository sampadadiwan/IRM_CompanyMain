class FundingRoundsController < ApplicationController
  before_action :set_funding_round, only: %i[show edit update destroy]

  # GET /funding_rounds or /funding_rounds.json
  def index
    @funding_rounds = policy_scope(FundingRound).order(id: :desc)
  end

  # GET /funding_rounds/1 or /funding_rounds/1.json
  def show; end

  # GET /funding_rounds/new
  def new
    @funding_round = FundingRound.new
    @funding_round.entity_id = current_user.entity_id
    @funding_round.currency = current_user.entity.currency
    authorize @funding_round
  end

  # GET /funding_rounds/1/edit
  def edit; end

  # POST /funding_rounds or /funding_rounds.json
  def create
    @funding_round = FundingRound.new(funding_round_params)
    @funding_round.entity_id = current_user.entity_id
    authorize @funding_round

    respond_to do |format|
      if @funding_round.save
        format.html { redirect_to funding_round_url(@funding_round), notice: "Funding round was successfully created." }
        format.json { render :show, status: :created, location: @funding_round }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @funding_round.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /funding_rounds/1 or /funding_rounds/1.json
  def update
    respond_to do |format|
      if @funding_round.update(funding_round_params)
        format.html { redirect_to funding_round_url(@funding_round), notice: "Funding round was successfully updated." }
        format.json { render :show, status: :ok, location: @funding_round }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @funding_round.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /funding_rounds/1 or /funding_rounds/1.json
  def destroy
    @funding_round.destroy

    respond_to do |format|
      format.html { redirect_to funding_rounds_url, notice: "Funding round was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_funding_round
    @funding_round = FundingRound.find(params[:id])
    authorize @funding_round
  end

  # Only allow a list of trusted parameters through.
  def funding_round_params
    params.require(:funding_round).permit(:name, :total_amount, :currency, :status,
                                          :pre_money_valuation, :entity_id, :closed_on,
                                          :liq_pref_type, :price, :anti_dilution)
  end
end
