class AiRulesController < ApplicationController
  before_action :set_ai_rule, only: %i[show edit update destroy]

  # GET /ai_rules
  def index
    @q = AiRule.ransack(params[:q])
    @ai_rules = policy_scope(@q.result)
    @pagy, @ai_rules = pagy(@ai_rules) unless params[:format] == "xlsx"
  end

  # GET /ai_rules/1
  def show; end

  # GET /ai_rules/new
  def new
    @ai_rule = AiRule.new
    @ai_rule.entity_id = current_user.entity_id
    authorize @ai_rule
  end

  # GET /ai_rules/1/edit
  def edit; end

  # POST /ai_rules
  def create
    @ai_rule = AiRule.new(ai_rule_params)
    @ai_rule.entity_id = current_user.entity_id
    authorize @ai_rule
    if @ai_rule.save
      redirect_to @ai_rule, notice: "Compliance rule was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /ai_rules/1
  def update
    if @ai_rule.update(ai_rule_params)
      redirect_to @ai_rule, notice: "Compliance rule was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /ai_rules/1
  def destroy
    @ai_rule.destroy!
    redirect_to ai_rules_url, notice: "Compliance rule was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ai_rule
    @ai_rule = AiRule.find(params[:id])
    authorize @ai_rule
  end

  # Only allow a list of trusted parameters through.
  def ai_rule_params
    params.require(:ai_rule).permit(:entity_id, :name, :for_class, :rule_type, :rule, :tags, :schedule, :enabled)
  end
end
