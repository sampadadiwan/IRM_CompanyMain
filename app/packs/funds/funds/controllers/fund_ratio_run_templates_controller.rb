# Manages FundRatioRunTemplate records and their trigger actions.
#
# Trigger actions (trigger_all, trigger_by_tag, trigger_one) enqueue
# FundRatiosScenarioJob for the matched templates and redirect back.
# They do NOT create or mutate template records.
class FundRatioRunTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy trigger_one runs]
  after_action  :verify_authorized

  # GET /fund_ratio_run_templates
  def index
    authorize FundRatioRunTemplate
    # All entity-scoped templates ordered by position then name.
    # distinct_tags is used to populate the "Run by Tag" dropdown.
    @templates    = policy_scope(FundRatioRunTemplate).ordered
    @distinct_tags = policy_scope(FundRatioRunTemplate).distinct_tags
  end

  # GET /fund_ratio_run_templates/new
  def new
    @template = FundRatioRunTemplate.new(entity: current_user.entity, user: current_user)
    authorize @template
  end

  # POST /fund_ratio_run_templates
  def create
    @template = FundRatioRunTemplate.new(template_params)
    @template.entity = current_user.entity
    @template.user   = current_user
    authorize @template

    if @template.save
      redirect_to fund_ratio_run_templates_path, notice: "Template '#{@template.name}' created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /fund_ratio_run_templates/:id/edit
  def edit
    authorize @template
  end

  # PATCH/PUT /fund_ratio_run_templates/:id
  def update
    authorize @template

    if @template.update(template_params)
      redirect_to fund_ratio_run_templates_path, notice: "Template '#{@template.name}' updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /fund_ratio_run_templates/:id
  def destroy
    authorize @template
    name = @template.name
    @template.destroy
    redirect_to fund_ratio_run_templates_path, notice: "Template '#{name}' deleted."
  end

  # GET /fund_ratio_run_templates/:id/runs
  # Lists every FundRatioRun produced by triggering this template (matched by fingerprint).
  def runs
    authorize @template, :show?
    @runs = @template.runs
  end

  # POST /fund_ratio_run_templates/trigger_all
  # Enqueues every entity template with the given end_date.
  def trigger_all
    authorize FundRatioRunTemplate, :trigger?
    end_date = parse_end_date(params[:end_date])
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?

    templates = policy_scope(FundRatioRunTemplate).ordered
    count = enqueue_templates(templates, end_date)
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued #{count} ratio #{"calculation".pluralize(count)} for #{end_date}."
  end

  # POST /fund_ratio_run_templates/trigger_by_tag
  # Enqueues only templates whose tag matches params[:tag].
  def trigger_by_tag
    authorize FundRatioRunTemplate, :trigger?
    end_date = parse_end_date(params[:end_date])
    tag      = params[:tag].to_s.strip
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "tag is required"      if tag.blank?

    templates = policy_scope(FundRatioRunTemplate).for_tag(tag).ordered
    count = enqueue_templates(templates, end_date)
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued #{count} ratio #{"calculation".pluralize(count)} for tag '#{tag}' on #{end_date}."
  end

  # POST /fund_ratio_run_templates/:id/trigger_one
  # Enqueues a single template.
  def trigger_one
    authorize @template, :trigger?
    end_date = parse_end_date(params[:end_date])
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?

    @template.enqueue(end_date: end_date, user_id: current_user.id)
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued '#{@template.name}' for #{end_date}."
  end

  private

  def set_template
    @template = FundRatioRunTemplate.find(params[:id])
  end

  # Calls #enqueue on each template and returns the count dispatched.
  def enqueue_templates(templates, end_date)
    templates.each { |t| t.enqueue(end_date: end_date, user_id: current_user.id) }
    templates.count
  end

  # Returns a Date or nil — never raises so the controller can give a clean error.
  def parse_end_date(raw)
    raw.present? ? Date.local_parse(raw) : nil
  rescue ArgumentError
    nil
  end

  def template_params
    params.require(:fund_ratio_run_template).permit(
      :name, :anchor_fund_id, :portfolio_companies_tags, :position,
      fund_ids: [], portfolio_company_ids: [], sectors: [], tags: []
    )
  end
end
