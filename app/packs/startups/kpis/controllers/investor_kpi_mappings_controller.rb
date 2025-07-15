class InvestorKpiMappingsController < ApplicationController
  after_action :verify_policy_scoped, only: [:index]
  after_action :verify_authorized, except: %i[index generate]
  before_action :set_investor_kpi_mapping, only: %i[show edit update destroy]

  # GET /investor_kpi_mappings or /investor_kpi_mappings.json
  def index
    @investor_kpi_mappings = policy_scope(InvestorKpiMapping).includes(:investor)
    @investor_kpi_mappings = @investor_kpi_mappings.where(investor_id: params[:investor_id]) if params[:investor_id].present?
  end

  # GET /investor_kpi_mappings/1 or /investor_kpi_mappings/1.json
  def show; end

  # GET /investor_kpi_mappings/new
  def new
    @investor_kpi_mapping = InvestorKpiMapping.new(investor_kpi_mapping_params)
    @investor_kpi_mapping.entity_id = current_user.entity_id
    authorize @investor_kpi_mapping
    setup_custom_fields(@investor_kpi_mapping)
  end

  # GET /investor_kpi_mappings/1/edit
  def edit
    setup_custom_fields(@investor_kpi_mapping)
  end

  # POST /investor_kpi_mappings or /investor_kpi_mappings.json
  def create
    @investor_kpi_mapping = InvestorKpiMapping.new(investor_kpi_mapping_params)
    authorize @investor_kpi_mapping
    respond_to do |format|
      if @investor_kpi_mapping.save
        format.html { redirect_to investor_kpi_mapping_url(@investor_kpi_mapping), notice: "Investor kpi mapping was successfully created." }
        format.json { render :show, status: :created, location: @investor_kpi_mapping }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_kpi_mapping.errors, status: :unprocessable_entity }
      end
    end
  end

  def generate
    investor = Investor.find(params[:investor_id])
    kpi_report = policy_scope(KpiReport).where(entity_id: investor.investor_entity_id).or(policy_scope(KpiReport).where(portfolio_company_id: investor.id)).last
    InvestorKpiMapping.create_from(current_user.entity, kpi_report)
    redirect_to investor_path(investor.id, tab: "kpi-mappings-tab"), notice: "Investor KPI Mappings generated"
  end

  # PATCH/PUT /investor_kpi_mappings/1 or /investor_kpi_mappings/1.json
  def update
    respond_to do |format|
      if @investor_kpi_mapping.update(investor_kpi_mapping_params)
        format.html { redirect_to investor_kpi_mapping_url(@investor_kpi_mapping), notice: "Investor kpi mapping was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_kpi_mapping }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_kpi_mapping.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_kpi_mappings/1 or /investor_kpi_mappings/1.json
  def destroy
    @investor_kpi_mapping.destroy!

    respond_to do |format|
      format.html { redirect_to investor_path(@investor_kpi_mapping.investor_id, tab: "kpi-mappings-tab"), notice: "Investor kpi mapping was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_kpi_mapping
    @investor_kpi_mapping = InvestorKpiMapping.find(params[:id])
    authorize @investor_kpi_mapping
    @bread_crumbs = { Mappings: investor_kpi_mappings_path(investor_id: @investor_kpi_mapping.investor_id), "#{@investor_kpi_mapping}": investor_kpi_mapping_path(@investor_kpi_mapping) }
  end

  # Only allow a list of trusted parameters through.
  def investor_kpi_mapping_params
    params.require(:investor_kpi_mapping).permit(:entity_id, :investor_id, :reported_kpi_name, :category, :standard_kpi_name, :lower_threshold, :upper_threshold, :data_type, :show_in_report, :form_type_id, rag_rules: {}, properties: {})
  end
end
