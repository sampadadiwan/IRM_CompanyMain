class FundsController < ApplicationController
  before_action :set_fund, only: %i[show edit update destroy]

  # GET /funds or /funds.json
  def index
    @funds = policy_scope(Fund)
  end

  # GET /funds/1 or /funds/1.json
  def show; end

  # GET /funds/new
  def new
    @fund = Fund.new
    @fund.entity_id = current_user.entity_id
    setup_custom_fields(@fund)
    authorize(@fund)
  end

  # GET /funds/1/edit
  def edit
    setup_custom_fields(@fund)
  end

  # POST /funds or /funds.json
  def create
    @fund = Fund.new(fund_params)
    @fund.entity_id = current_user.entity_id
    authorize(@fund)
    respond_to do |format|
      if @fund.save
        format.html { redirect_to fund_url(@fund), notice: "Fund was successfully created." }
        format.json { render :show, status: :created, location: @fund }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @fund.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /funds/1 or /funds/1.json
  def update
    @fund.entity_id = current_user.entity_id
    respond_to do |format|
      if @fund.update(fund_params)
        format.html { redirect_to fund_url(@fund), notice: "Fund was successfully updated." }
        format.json { render :show, status: :ok, location: @fund }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @fund.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /funds/1 or /funds/1.json
  def destroy
    @fund.destroy

    respond_to do |format|
      format.html { redirect_to funds_url, notice: "Fund was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_fund
    @fund = Fund.find(params[:id])
    authorize(@fund)
  end

  # Only allow a list of trusted parameters through.
  def fund_params
    params.require(:fund).permit(:name, :committed_amount, :details, :collected_amount, :entity_id, :tag_list, properties: {})
  end
end
