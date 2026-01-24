# Controller for managing investment criteria templates.
#
# Provides CRUD operations for InvestmentCriteriaTemplate records, allowing users
# to create reusable sets of investment evaluation criteria. All actions are
# scoped to the current user's entity via Pundit authorization.
# @see InvestmentCriteriaTemplate
# @see InvestmentCriteriaTemplateService
# @see InvestmentCriteriaTemplatePolicy
class InvestmentCriteriaTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy preview]

  # GET /investment_criteria_templates
  # Lists all templates for the current user, ordered by usage frequency.
  def index
    @templates = policy_scope(InvestmentCriteriaTemplate).order(usage_count: :desc)
    respond_to do |format|
      format.html
      format.json { render json: @templates }
    end
  end

  # GET /investment_criteria_templates/new
  # Renders the form for creating a new template.
  def new
    @template = InvestmentCriteriaTemplate.new
    authorize @template
  end

  # POST /investment_criteria_templates
  # Creates a new template using the InvestmentCriteriaTemplateService.
  # Redirects to show on success, re-renders form on validation failure.
  def create
    authorize InvestmentCriteriaTemplate
    service = InvestmentCriteriaTemplateService.new(current_user)
    @template = service.create(
      name: template_params[:name],
      criteria: parse_criteria_params
    )
    redirect_to @template, notice: 'Template created successfully'
  rescue ActiveRecord::RecordInvalid => e
    @template = e.record
    render :new
  end

  # GET /investment_criteria_templates/:id
  # Displays a single template.
  def show; end

  # GET /investment_criteria_templates/:id/edit
  # Renders the form for editing an existing template.
  def edit; end

  # GET /investment_criteria_templates/:id/preview
  # Returns the template data as JSON for AJAX preview.
  #
  # @return [JSON] hash containing name and criteria
  def preview
    render json: { name: @template.name, criteria: @template.criteria }
  end

  # PATCH/PUT /investment_criteria_templates/:id
  # Updates an existing template using the InvestmentCriteriaTemplateService.
  def update
    service = InvestmentCriteriaTemplateService.new(current_user)
    service.update(@template,
                   name: template_params[:name],
                   criteria: parse_criteria_params)
    redirect_to @template, notice: 'Template updated'
  end

  # DELETE /investment_criteria_templates/:id
  # Destroys the template and redirects to the index.
  def destroy
    @template.destroy
    redirect_to investment_criteria_templates_path
  end

  private

  # Finds and authorizes the template from params[:id], scoped to current user's entity.
  # @return [void]
  # @raise [ActiveRecord::RecordNotFound] if template not found for user
  def set_template
    @template = current_user.entity.investment_criteria_templates.find(params[:id])
    authorize @template
  end

  # Strong parameters for template attributes.
  #
  # @return [ActionController::Parameters] permitted parameters
  def template_params
    params.require(:investment_criteria_template).permit(:name, criteria: %i[name value])
  end

  # Parses criteria params from the dynamic form fields.
  # Converts indexed form params to an array of criterion hashes,
  # filtering out any entries with blank names.
  #
  # @return [Array<Hash>] array of criteria hashes with :name and :value keys
  def parse_criteria_params
    params[:criteria]&.values&.reject { |c| c[:name].blank? } || []
  end
end
