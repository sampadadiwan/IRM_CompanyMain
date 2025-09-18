class AgentChartsController < ApplicationController
  before_action :set_agent_chart, only: %i[show edit update destroy regenerate]

  # GET /agent_charts
  def index
    @q = AgentChart.ransack(params[:q])
    @agent_charts = policy_scope(@q.result)
  end

  # GET /agent_charts/1
  def show; end

  # GET /agent_charts/new
  def new
    @agent_chart = AgentChart.new
    @agent_chart.entity_id = current_user.entity_id
    @agent_chart.status = "pending"
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
    AgentChartJob.perform_later(@agent_chart.id, current_user.id)
    redirect_to @agent_chart, notice: "Chart regeneration initiated.", status: :see_other
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
    params.require(:agent_chart).permit(:title, :prompt, :raw_data, :spec, :llm_model, :status, :error, :document_ids)
  end
end
