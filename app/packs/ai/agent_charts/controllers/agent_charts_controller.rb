class AgentChartsController < ApplicationController
  before_action :set_agent_chart, only: %i[show edit update destroy regenerate]

  # GET /agent_charts
  def index
    @q = AgentChart.ransack(params[:q])
    @agent_charts = policy_scope(@q.result)
    @agent_charts = @agent_charts.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
  end

  # GET /agent_charts/1
  def show
    # Preload all Investors that have a saved spec in one query to avoid N+1
    # when the dropdown and chart title both call Investor.find(portfolio_company_id).
    # index_by with a string key mirrors the string keys stored in spec (JSON round-trip).
    @portfolio_companies =
      if @agent_chart.spec.present?
        Investor.where(id: @agent_chart.spec.keys).index_by { |pc| pc.id.to_s }
      else
        {}
      end

    # Portfolio companies available for generation — scoped to the chart's tag_list when
    # present so the multi-select mirrors what the job would run against.
    base = @agent_chart.entity.investors.portfolio_companies.order(:investor_name)
    @candidate_companies = if @agent_chart.tag_list.present?
      base.with_tag_list(@agent_chart.tag_list)
    else
      base
    end
  end

  # GET /agent_charts/new
  def new
    @agent_chart = AgentChart.new
    @agent_chart.entity_id = current_user.entity_id
    # "draft" is the correct initial status; "pending" is not in AgentChart::STATUSES
    # and would cause a validation error on save.
    @agent_chart.status = "draft"
    @agent_chart.owner_id = params[:owner_id]
    @agent_chart.owner_type = params[:owner_type]
    authorize @agent_chart
  end

  # GET /agent_charts/1/edit
  def edit; end

  # POST /agent_charts
  def create
    @agent_chart = AgentChart.new(agent_chart_params)
    @agent_chart.entity_id = current_user.entity_id
    @agent_chart.status ||= "draft"
    authorize @agent_chart

    if @agent_chart.save
      redirect_to @agent_chart, notice: "Agent chart was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /agent_charts/1
  def update
    if @agent_chart.update(agent_chart_params)
      redirect_to @agent_chart, notice: "Agent chart was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def regenerate
    # "Generate for Selected" sends portfolio_company_ids[]; "Generate for All" sends none.
    ids = Array(params[:portfolio_company_ids]).map(&:to_i).presence

    if ids
      AgentChartJob.perform_later(current_user.id, agent_chart_id: @agent_chart.id, portfolio_company_ids: ids)
      notice = "Generating chart for #{ids.size} portfolio #{"company".pluralize(ids.size)}…"
    else
      AgentChartJob.perform_later(current_user.id, agent_chart_id: @agent_chart.id)
      notice = "Generating chart for all matching portfolio companies…"
    end

    redirect_to @agent_chart, notice: notice, status: :see_other
  end

  # DELETE /agent_charts/1
  def destroy
    @agent_chart.destroy!
    redirect_to agent_charts_url, notice: "Agent chart was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_agent_chart
    @agent_chart = AgentChart.find(params[:id])
    authorize @agent_chart
  end

  # Only allow a list of trusted parameters through.
  def agent_chart_params
    params.require(:agent_chart).permit(
      :title, :prompt, :raw_data, :spec, :llm_model, :status,
      :tag_list, :error, :document_names, :kpi_before, :kpi_before_period,
      :chart_height,   # user-controlled canvas height in pixels; nil uses JS default
      kpi_names: []
    )
  end
end
