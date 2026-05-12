class ValidationRuleOverridesController < ApplicationController
  skip_after_action :verify_policy_scoped

  before_action :set_override, only: %i[edit update destroy]

  # GET /validation_rule_overrides
  # Displays all global default rules grouped by model, with the current entity's
  # override state inline so a company_admin can see exactly what is active.
  def index
    authorize ValidationRuleOverride

    # All global defaults relevant to the engine, ordered for display
    @rules_by_model = ValidationRule
                        .global_defaults
                        .where(target_model: ValidationRuleEvaluator::CONTEXT_PROVIDERS.keys)
                        .order(:target_model, :name)
                        .group_by(&:target_model)

    # Preload overrides for this entity keyed by rule id — avoids N+1 in the view
    @overrides_by_rule_id = ValidationRuleOverride
                              .where(entity_id: current_user.entity_id)
                              .index_by(&:validation_rule_id)
  end

  # GET /validation_rule_overrides/new?validation_rule_id=X
  def new
    rule      = ValidationRule.find(params[:validation_rule_id])
    @override = ValidationRuleOverride.new(validation_rule: rule, entity_id: current_user.entity_id, enabled: true)
    authorize @override
  end

  # POST /validation_rule_overrides
  def create
    @override = ValidationRuleOverride.new(override_params)
    @override.entity_id = current_user.entity_id
    authorize @override

    if @override.save
      redirect_to validation_rule_overrides_path, notice: "Override saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /validation_rule_overrides/:id/edit
  def edit
    authorize @override
  end

  # PATCH /validation_rule_overrides/:id
  def update
    authorize @override

    if @override.update(override_params)
      redirect_to validation_rule_overrides_path, notice: "Override updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /validation_rule_overrides/:id
  # Removes the override — the rule reverts to its global default behaviour.
  def destroy
    authorize @override
    @override.destroy
    redirect_to validation_rule_overrides_path, notice: "Override removed. Rule reverted to global default."
  end

  private

  def set_override
    # Scoped to current entity so a company_admin cannot touch another entity's overrides
    @override = ValidationRuleOverride.find_by!(
      id:        params[:id],
      entity_id: current_user.entity_id
    )
  end

  def override_params
    permitted = params.require(:validation_rule_override)
                      .permit(:validation_rule_id, :enabled, :severity_override, :message_override)

    # param_overrides is a free-form hash — permit! is safe here since it's only applied
    # to threshold values and the record is scoped to the current entity
    raw_param_overrides = params.dig(:validation_rule_override, :param_overrides)
    permitted[:param_overrides] = raw_param_overrides.present? ? raw_param_overrides.permit!.to_h : {}

    permitted
  end
end
