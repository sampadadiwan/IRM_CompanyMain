class InvestmentSnapshotsController < ApplicationController
  before_action :set_investment_snapshot, only: %i[show edit update destroy]

  # GET /investment_snapshots or /investment_snapshots.json
  def index
    @investment_snapshots = policy_scope(InvestmentSnapshot).includes(:investor, :funding_round, :entity)
  end

  # GET /investment_snapshots/1 or /investment_snapshots/1.json
  def show; end

  # GET /investment_snapshots/new
  def new
    @investment_snapshot = InvestmentSnapshot.new
    authorize @investment_snapshot
  end

  # GET /investment_snapshots/1/edit
  def edit; end

  # POST /investment_snapshots or /investment_snapshots.json
  def create
    @investment_snapshot = InvestmentSnapshot.new(investment_snapshot_params)
    authorize @investment_snapshot

    respond_to do |format|
      if @investment_snapshot.save
        format.html { redirect_to investment_snapshot_url(@investment_snapshot), notice: "Investment snapshot was successfully created." }
        format.json { render :show, status: :created, location: @investment_snapshot }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investment_snapshot.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investment_snapshots/1 or /investment_snapshots/1.json
  def update
    respond_to do |format|
      if @investment_snapshot.update(investment_snapshot_params)
        format.html { redirect_to investment_snapshot_url(@investment_snapshot), notice: "Investment snapshot was successfully updated." }
        format.json { render :show, status: :ok, location: @investment_snapshot }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investment_snapshot.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investment_snapshots/1 or /investment_snapshots/1.json
  def destroy
    @investment_snapshot.destroy

    respond_to do |format|
      format.html { redirect_to investment_snapshots_url, notice: "Investment snapshot was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment_snapshot
    @investment_snapshot = InvestmentSnapshot.find(params[:id])
    authorize @investment_snapshot
  end

  # Only allow a list of trusted parameters through.
  def investment_snapshot_params
    params.require(:investment_snapshot).permit(:investment_type, :investor_id, :investor_type, :entity_id, :status, :investment_instrument, :quantity, :initial_value, :current_value, :category, :deleted_at, :percentage_holding, :employee_holdings, :diluted_quantity, :diluted_percentage, :currency, :units, :amount_cents, :price_cents, :funding_round_id, :liquidation_preference, :spv, :investment_date, :liq_pref_type, :anti_dilution, :as_of, :tag, :investment_id)
  end
end
