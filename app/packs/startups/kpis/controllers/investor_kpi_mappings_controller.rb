class InvestorKpiMappingsController < ApplicationController
  after_action :verify_policy_scoped, only: [:index]
  after_action :verify_authorized, except: %i[index generate]
  before_action :set_investor_kpi_mapping, only: %i[show edit update destroy recompute_rag]

  # GET /investor_kpi_mappings or /investor_kpi_mappings.json
  def index
    @investor_kpi_mappings = policy_scope(InvestorKpiMapping).includes(:investor)
    @investor_kpi_mappings = filter_params(@investor_kpi_mappings, :investor_id, :import_upload_id)
    respond_to do |format|
      format.html
      format.xlsx
      format.json
    end
  end

  # GET /investor_kpi_mappings/1 or /investor_kpi_mappings/1.json
  def show; end

  # GET /investor_kpi_mappings/new
  def new
    @investor_kpi_mapping = InvestorKpiMapping.new(investor_kpi_mapping_params)
    @investor_kpi_mapping.entity_id = current_user.entity_id
    @investor_kpi_mapping.data_type = 'money' # Default data type
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
        # The portco's first mapping passes "Set up KPI mappings" on its open KPI report journeys
        # Worked examples H15 — openspec/changes/kpi-report-journey/design.md#worked-examples
        KpiReport.journey_progress_for_portco(@investor_kpi_mapping.entity_id, @investor_kpi_mapping.investor_id, actor: current_user)
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

  # Re-runs RAG evaluation for every approved KPI reported under this mapping — for when rules
  # were added/edited after KPIs using it were already approved (recompute_rag_status! only
  # fires from a Kpi's own after_save, so a rule change alone never touches existing rows).
  # Queued rather than run inline, matching KpiApproveService's KpiCumulateJob/
  # KpiPercentageChangeJob triggers elsewhere in this controller family — see
  # RecomputeInvestorKpiMappingRagJob for why.
  def recompute_rag
    RecomputeInvestorKpiMappingRagJob.perform_later(@investor_kpi_mapping.id, current_user.id)
    redirect_to investor_kpi_mapping_url(@investor_kpi_mapping), notice: "RAG recompute queued — you'll get a notification when it's done."
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
  # Refused for a parent mapping; otherwise deletes the mapping and the KPIs that use it (the page's
  # popup warned how many) — never an error page.
  # Worked examples H11, H13, X2, X5 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def destroy
    result = InvestorKpiMappingDelete.call(mapping: @investor_kpi_mapping, user: current_user)

    respond_to do |format|
      if result.success?
        deleted = result[:kpis_deleted].to_i
        notice = if deleted.positive?
                   "#{@investor_kpi_mapping.reported_kpi_name} and #{helpers.pluralize(deleted, 'KPI')} deleted."
                 else
                   "Investor kpi mapping was successfully destroyed."
                 end
        format.html { redirect_to investor_path(@investor_kpi_mapping.investor_id, tab: "kpi-mappings-tab"), notice: }
        format.json { head :no_content }
      else
        format.html { redirect_to investor_kpi_mapping_path(@investor_kpi_mapping), alert: result[:error] }
        format.json { render json: { error: result[:error] }, status: :unprocessable_entity }
      end
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
  # fx_conversion_method added for KPI currency conversion — controls how values are
  # converted from portco's reporting currency to fund's base currency at upload time.
  def investor_kpi_mapping_params
    params.require(:investor_kpi_mapping).permit(:entity_id, :investor_id, :reported_kpi_name, :position, :category, :standard_kpi_name, :autofill, :compute_formula, :base_for_common_size, :lower_threshold, :upper_threshold, :data_type, :denomination, :fx_conversion_method, :parent_id, :show_in_report, :form_type_id, :rag_comparator_tag, :rag_direction, :rag_red_threshold, :rag_green_threshold, :source_sheet, properties: {})
  end
end
