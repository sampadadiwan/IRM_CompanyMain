# CRUD for AllocationRunTemplateGroup and the two-step trigger: preflight shows the up-front
# checks for a period and either lists what would fail (nothing runs) or asks for
# confirmation; run records the group run and enqueues the job.
class AllocationRunTemplateGroupsController < ApplicationController
  helper AllocationRunTemplatesHelper
  before_action :set_group, only: %i[show edit update destroy preflight run]
  after_action :verify_authorized

  def new
    @group = AllocationRunTemplateGroup.new(entity: current_user.entity, user: current_user)
    authorize @group
  end

  def create
    @group = AllocationRunTemplateGroup.new(group_params)
    @group.entity = current_user.entity
    @group.user = current_user
    authorize @group

    if @group.save
      redirect_to allocation_run_template_group_path(@group), notice: "Allocation run group \"#{@group.name}\" saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /allocation_run_template_groups/:id — tabs: templates (run order), runs (history)
  def show
    authorize @group
    @runs = @group.allocation_group_runs.includes(:items).recent
    @active_run = @group.active_run
    @tab = %w[templates runs].include?(params[:tab]) ? params[:tab] : "templates"
  end

  def edit
    authorize @group
  end

  def update
    # Assign (but don't yet save) so accepts_nested_attributes_for builds/marks the items
    # in memory first — authorize must check the composition being submitted, not the one
    # already on record, or adding a fund via nested attributes would never be checked.
    @group.assign_attributes(group_params)
    authorize @group
    if @group.save
      redirect_to allocation_run_template_group_path(@group), notice: "Allocation run group \"#{@group.name}\" updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Decision 17: run history is kept (allocation_group_runs are nullified, not destroyed).
  def destroy
    authorize @group
    name = @group.name
    @group.destroy
    redirect_to allocation_run_templates_path, notice: "Allocation run group \"#{name}\" deleted. Its run history is kept."
  end

  # GET /allocation_run_template_groups/:id/preflight?start_date=&end_date=&resume=
  def preflight
    authorize @group
    read_run_params
    result = AllocationGroupRunPreflight.call(group: @group, user: current_user,
                                              start_date: @start_date, end_date: @end_date, resume: @resume)
    @checks = result[:checks]
    @group_blockers = result[:group_blockers]
    @startable = result[:startable]
    @resume_from = result[:resume_from]
  end

  # POST /allocation_run_template_groups/:id/run
  def run
    authorize @group
    read_run_params
    result = AllocationGroupRunStart.call(group: @group, user: current_user,
                                          start_date: @start_date, end_date: @end_date, resume: @resume)
    if result.success?
      redirect_to allocation_group_run_path(result[:group_run]),
                  notice: "Allocation run group \"#{@group.name}\" started for #{l(@start_date)} – #{l(@end_date)}. Templates run one after another; you will be alerted and emailed when it finishes."
    else
      # State changed since the pre-flight page (another group started, a run was locked…):
      # show the fresh check results rather than a bare error.
      redirect_to preflight_allocation_run_template_group_path(@group, start_date: @start_date, end_date: @end_date, resume: @resume ? 1 : 0),
                  alert: result[:error] || result[:group_blockers]&.first || "The group could not be started."
    end
  end

  private

  def set_group
    # Preloaded because every action here (show/edit/update/destroy/preflight/run) authorizes
    # the group, and AllocationRunTemplateGroupPolicy#all_funds_permitted? walks record.items
    # -> allocation_run_template -> fund; without this it's an N+1 on every request.
    @group = policy_scope(AllocationRunTemplateGroup).includes(items: { allocation_run_template: :fund }).find(params[:id])
  end

  def group_params
    params.require(:allocation_run_template_group).permit(
      :name, :description,
      items_attributes: %i[id allocation_run_template_id position _destroy]
    )
  end

  # Dates come from the Run modal (locale-formatted display input plus hidden ISO input);
  # resume defaults to on — decision 8(c).
  def read_run_params
    @start_date = parse_date(params[:start_date])
    @end_date = parse_date(params[:end_date])
    @resume = params[:resume].to_s != "0"
  end

  def parse_date(raw)
    raw.present? ? Date.local_parse(raw) : nil
  rescue ArgumentError
    nil
  end
end
