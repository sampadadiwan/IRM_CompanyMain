class CapitalCommitmentsController < ApplicationController
  before_action :set_capital_commitment, only: %i[show edit update destroy]

  # GET /capital_commitments or /capital_commitments.json
  def index
    @capital_commitments = policy_scope(CapitalCommitment)
  end

  # GET /capital_commitments/1 or /capital_commitments/1.json
  def show; end

  # GET /capital_commitments/new
  def new
    @capital_commitment = CapitalCommitment.new(capital_commitment_params)
    authorize @capital_commitment
  end

  # GET /capital_commitments/1/edit
  def edit; end

  # POST /capital_commitments or /capital_commitments.json
  def create
    @capital_commitment = CapitalCommitment.new(capital_commitment_params)
    authorize @capital_commitment
    respond_to do |format|
      if @capital_commitment.save
        format.html { redirect_to capital_commitment_url(@capital_commitment), notice: "Capital commitment was successfully created." }
        format.json { render :show, status: :created, location: @capital_commitment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_commitment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_commitments/1 or /capital_commitments/1.json
  def update
    respond_to do |format|
      if @capital_commitment.update(capital_commitment_params)
        format.html { redirect_to capital_commitment_url(@capital_commitment), notice: "Capital commitment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_commitment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_commitment.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /capital_commitments/1 or /capital_commitments/1.json
  def destroy
    @capital_commitment.destroy

    respond_to do |format|
      format.html { redirect_to capital_commitments_url, notice: "Capital commitment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_commitment
    @capital_commitment = CapitalCommitment.find(params[:id])
    authorize @capital_commitment
  end

  # Only allow a list of trusted parameters through.
  def capital_commitment_params
    params.require(:capital_commitment).permit(:entity_id, :investor_id, :fund_id, :committed_amount, :collected_amount, :notes)
  end
end
