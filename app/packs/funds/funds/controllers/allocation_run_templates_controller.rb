# CRUD for AllocationRunTemplate plus the one page that lists templates, groups and run
# history together (the "Allocation Run Templates" page under Funds).
#
# A template is created either from scratch (new/create with the full form) or from a past
# AllocationRun via "Save as allocation run template" on the allocation screen, which posts
# only a name and the run id (from_allocation_run_id) to create.
class AllocationRunTemplatesController < ApplicationController
  helper AllocationRunTemplatesHelper
  before_action :set_template, only: %i[show edit update destroy]
  after_action :verify_authorized

  # GET /allocation_run_templates — tabs: groups, templates, run history
  def index
    authorize AllocationRunTemplate
    @templates = policy_scope(AllocationRunTemplate).includes(:fund, :statement_document, :allocation_run_template_groups).ordered
    @groups = policy_scope(AllocationRunTemplateGroup).includes(items: { allocation_run_template: :fund }).ordered
    @group_runs = policy_scope(AllocationGroupRun).includes(:items).recent.limit(50)
    @active_run = AllocationGroupRun.active_for_entity(current_user.entity_id)
    @tab = %w[groups templates runs].include?(params[:tab]) ? params[:tab] : "groups"
  end

  # GET /allocation_run_templates/new?from_allocation_run_id=… (optional pre-fill)
  def new
    @template = build_template
    authorize @template
  end

  # POST /allocation_run_templates
  def create
    @template = build_template
    @template.assign_attributes(template_params) if params[:allocation_run_template].present?
    authorize @template

    if @template.save
      redirect_to after_save_path(@template), notice: "Allocation run template \"#{@template.name}\" saved."
    elsif params[:return_to].present?
      # The "Save as template" modal on the allocation screen has no form to re-render — send
      # the person back there with the reason so they can try again.
      redirect_to safe_return_to, alert: @template.errors.full_messages.join(", ")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /allocation_run_templates/:id — tabs: details, groups, runs
  def show
    authorize @template
    @run_items = @template.allocation_group_run_items.includes(:allocation_group_run, :allocation_run).order(created_at: :desc)
    @tab = %w[details groups runs].include?(params[:tab]) ? params[:tab] : "details"
  end

  def edit
    authorize @template
  end

  def update
    authorize @template
    if @template.update(template_params)
      redirect_to allocation_run_template_path(@template), notice: "Allocation run template \"#{@template.name}\" updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Decision 17: refused (restrict_with_error) while the template is still in a group.
  def destroy
    authorize @template
    name = @template.name
    if @template.destroy
      redirect_to allocation_run_templates_path(tab: "templates"), notice: "Allocation run template \"#{name}\" deleted."
    else
      redirect_to allocation_run_template_path(@template), alert: @template.errors.full_messages.join(", ")
    end
  end

  # GET /allocation_run_templates/statement_documents?fund_id=… (JSON)
  # The statement-document select on the form is refilled from this when the fund changes.
  def statement_documents
    authorize AllocationRunTemplate
    fund = policy_scope(Fund).find(params[:fund_id])
    docs = fund.documents.templates.where(owner_tag: AllocationRunTemplate::STATEMENT_DOCUMENT_TAGS).order(:name)
    render json: docs.map { |d| { id: d.id, name: d.name } }
  end

  private

  def set_template
    @template = policy_scope(AllocationRunTemplate).find(params[:id])
  end

  # A blank template, or one pre-filled from a past run of a fund in this entity.
  def build_template
    template = if params[:from_allocation_run_id].present?
                 run = AllocationRun.find_by!(id: params[:from_allocation_run_id], entity_id: current_user.entity_id)
                 @from_run = run
                 AllocationRunTemplate.from_allocation_run(run)
               else
                 AllocationRunTemplate.new(fund_id: params[:fund_id])
               end
    template.entity = current_user.entity
    template.user = current_user
    template
  end

  def template_params
    params.require(:allocation_run_template).permit(
      :name, :description, :fund_id, :rule_for, :run_allocations, :generate_soa, :statement_for,
      :statement_document_id, :fund_ratios, :explain, :sample, tags: []
    )
  end

  # After "Save as template" go back to the allocation screen; otherwise show the template.
  def after_save_path(template)
    params[:return_to].present? ? safe_return_to : allocation_run_template_path(template)
  end

  # Only same-site paths are honoured, never a full URL.
  def safe_return_to
    value = params[:return_to].to_s
    value.start_with?("/") && !value.start_with?("//") ? value : allocation_run_templates_path
  end
end
