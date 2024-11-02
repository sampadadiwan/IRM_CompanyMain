class ComplianceRulesController < ApplicationController
  before_action :set_compliance_rule, only: %i[show edit update destroy]

  # GET /compliance_rules
  def index
    @q = ComplianceRule.ransack(params[:q])
    @compliance_rules = policy_scope(@q.result)
  end

  # GET /compliance_rules/1
  def show; end

  # GET /compliance_rules/new
  def new
    @compliance_rule = ComplianceRule.new
    @compliance_rule.entity_id = current_user.entity_id
    authorize @compliance_rule
  end

  # GET /compliance_rules/1/edit
  def edit; end

  # POST /compliance_rules
  def create
    @compliance_rule = ComplianceRule.new(compliance_rule_params)
    @compliance_rule.entity_id = current_user.entity_id
    authorize @compliance_rule
    if @compliance_rule.save
      redirect_to @compliance_rule, notice: "Compliance rule was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /compliance_rules/1
  def update
    if @compliance_rule.update(compliance_rule_params)
      redirect_to @compliance_rule, notice: "Compliance rule was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /compliance_rules/1
  def destroy
    @compliance_rule.destroy!
    redirect_to compliance_rules_url, notice: "Compliance rule was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_compliance_rule
    @compliance_rule = ComplianceRule.find(params[:id])
    authorize @compliance_rule
  end

  # Only allow a list of trusted parameters through.
  def compliance_rule_params
    params.require(:compliance_rule).permit(:entity_id, :for_class, :rule, :tags, :schedule, :enabled)
  end
end
