class SupportAgentsController < ApplicationController
  before_action :set_support_agent, only: %i[show edit update destroy]

  # GET /support_agents
  def index
    @q = SupportAgent.ransack(params[:q])
    @support_agents = policy_scope(@q.result)
  end

  # GET /support_agents/1
  def show; end

  # GET /support_agents/new
  def new
    @support_agent = SupportAgent.new
    @support_agent.entity_id = current_user.entity_id
    authorize @support_agent
  end

  # GET /support_agents/1/edit
  def edit; end

  # POST /support_agents
  def create
    @support_agent = SupportAgent.new(support_agent_params)
    @support_agent.entity_id = current_user.entity_id
    authorize @support_agent
    if @support_agent.save
      redirect_to @support_agent, notice: "Support agent was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /support_agents/1
  def update
    if @support_agent.update(support_agent_params)
      redirect_to @support_agent, notice: "Support agent was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /support_agents/1
  def destroy
    @support_agent.destroy!
    redirect_to support_agents_url, notice: "Support agent was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_support_agent
    @support_agent = SupportAgent.find(params[:id])
    authorize @support_agent
    @bread_crumbs = { 'Support Agents': support_agents_path, "#{@support_agent.name}": support_agent_path(@support_agent) }
  end

  # Only allow a list of trusted parameters through.
  def support_agent_params
    params.require(:support_agent).permit(:name, :description, :entity_id, :form_type_id, :agent_type, :json_fields, :document_folder_id, properties: {})
  end
end
