class ShareTransfersController < ApplicationController
  before_action :set_share_transfer, only: %i[show edit update destroy]

  # GET /share_transfers or /share_transfers.json
  def index
    @share_transfers = policy_scope(ShareTransfer)
  end

  # GET /share_transfers/1 or /share_transfers/1.json
  def show; end

  # GET /share_transfers/new
  def new
    @share_transfer = ShareTransfer.new(share_transfer_params)
    @share_transfer.entity_id = current_user.entity_id
    @share_transfer.transfer_date = Time.zone.today
    @share_transfer.transfer_type ||= "Transfer"

    if @share_transfer.from_investment.present?
      authorize(@share_transfer.from_investment, :update?)
      @share_transfer.from_investor = @share_transfer.from_investment.investor
    end

    authorize(@share_transfer)
  end

  # GET /share_transfers/1/edit
  def edit; end

  # POST /share_transfers or /share_transfers.json
  def create
    @share_transfer = ShareTransfer.new(share_transfer_params)
    @share_transfer.transfered_by = current_user
    authorize(@share_transfer)

    if @share_transfer.from_investment
      result = DoShareTransfer.call(share_transfer: @share_transfer)
    elsif @share_transfer.from_holding
      result = DoHoldingTransfer.call(share_transfer: @share_transfer)
    end

    respond_to do |format|
      if result.failure? && !@share_transfer.valid?
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @share_transfer.errors, status: :unprocessable_entity }
      else
        format.html { redirect_to share_transfer_url(@share_transfer), notice: "Share transfer was successfully created." }
        format.json { render :show, status: :created, location: @share_transfer }
      end
    end
  end

  # PATCH/PUT /share_transfers/1 or /share_transfers/1.json
  def update
    respond_to do |format|
      if @share_transfer.update(share_transfer_params)
        format.html { redirect_to share_transfer_url(@share_transfer), notice: "Share transfer was successfully updated." }
        format.json { render :show, status: :ok, location: @share_transfer }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @share_transfer.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /share_transfers/1 or /share_transfers/1.json
  def destroy
    @share_transfer.destroy

    respond_to do |format|
      format.html { redirect_to share_transfers_url, notice: "Share transfer was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_share_transfer
    @share_transfer = ShareTransfer.find(params[:id])
    authorize(@share_transfer)
  end

  # Only allow a list of trusted parameters through.
  def share_transfer_params
    params.require(:share_transfer).permit(:entity_id, :from_investor_id, :from_holding_id, :from_investment_id,
                                           :to_investor_id, :to_holding_id, :to_investment_id, :quantity,
                                           :price, :transfer_date, :transfered_by_id, :transfer_type)
  end
end
