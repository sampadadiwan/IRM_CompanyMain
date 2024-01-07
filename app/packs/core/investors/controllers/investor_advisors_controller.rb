class InvestorAdvisorsController < ApplicationController
  before_action :set_investor_advisor, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index switch]

  # GET /investor_advisors or /investor_advisors.json
  def index
    @investor_advisors = policy_scope(InvestorAdvisor).includes(:entity, user: :entity)
    @investor_advisors = @investor_advisors.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
  end

  # GET /investor_advisors/1 or /investor_advisors/1.json
  def show; end

  # GET /investor_advisors/new
  def new
    @investor_advisor = InvestorAdvisor.new(investor_advisor_params)
    authorize(@investor_advisor)
  end

  # GET /investor_advisors/1/edit
  def edit; end

  # POST /investor_advisors or /investor_advisors.json
  def create
    @investor_advisor = InvestorAdvisor.new(investor_advisor_params)
    authorize(@investor_advisor)

    respond_to do |format|
      if @investor_advisor.save
        format.html { redirect_to investor_advisor_url(@investor_advisor), notice: "Investor advisor was successfully created." }
        format.json { render :show, status: :created, location: @investor_advisor }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_advisor.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_advisors/1 or /investor_advisors/1.json
  def update
    respond_to do |format|
      if @investor_advisor.update(investor_advisor_params)
        format.html { redirect_to investor_advisor_url(@investor_advisor), notice: "Investor advisor was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_advisor }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_advisor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_advisors/1 or /investor_advisors/1.json
  def destroy
    @investor_advisor.destroy

    respond_to do |format|
      format.html { redirect_to investor_advisors_url, notice: "Investor advisor was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def switch
    if params[:id].present?
      @investor_advisor = InvestorAdvisor.find(params[:id])
      authorize(@investor_advisor)
      # Switch to advisor
      @investor_advisor.switch(current_user)

      redirect_back(fallback_location: root_path, notice: "You have now been switched to the advisor role for #{@investor_advisor.entity.name}.")
    else
      # Switch back to normal
      InvestorAdvisor.revert(current_user)
      redirect_back(fallback_location: root_path, notice: "You have now been switched out of the advisor role.")
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_advisor
    @investor_advisor = InvestorAdvisor.find(params[:id])
    authorize(@investor_advisor)
  end

  # Only allow a list of trusted parameters through.
  def investor_advisor_params
    params.require(:investor_advisor).permit(:entity_id, :user_id, :email, allowed_roles: [], permissions: [], extended_permissions: [])
  end
end
