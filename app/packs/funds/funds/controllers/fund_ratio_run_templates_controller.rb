# Manages FundRatioRunTemplate records and their trigger actions.
#
# Trigger actions (trigger_all, trigger_by_tag, trigger_one) enqueue
# FundRatiosScenarioJob for the matched templates and redirect back.
# They do NOT create or mutate template records.
class FundRatioRunTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy trigger_one runs]
  before_action :coerce_portfolio_companies_tags, only: %i[create update]
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
    count, _warnings = enqueue_templates(templates, end_date)
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
    count, _warnings = enqueue_templates(templates, end_date)
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued #{count} ratio #{"calculation".pluralize(count)} for tag '#{tag}' on #{end_date}."
  end

  # POST /fund_ratio_run_templates/:id/trigger_one
  # Enqueues a single template.
  def trigger_one
    authorize @template, :trigger?
    end_date = parse_end_date(params[:end_date])
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?

    @template.trigger_end_date = end_date
    violations = ValidationRuleEvaluator.call(record: @template, entity: current_user.entity)
    blockers = violations.select(&:blocker?)
    if blockers.any?
      return redirect_to fund_ratio_run_templates_path,
                         alert: "Cannot enqueue '#{@template.name}': #{blockers.map(&:message).join("; ")}"
    end

    @template.enqueue(end_date: end_date, user_id: current_user.id)
    redirect_to fund_ratio_run_templates_path, notice: "Enqueued '#{@template.name}' for #{end_date}."
  end

  private

  def set_template
    @template = FundRatioRunTemplate.find(params[:id])
  end

  # Validates and enqueues each template. Returns [count_enqueued, warning_messages].
  # Templates with blocker violations are skipped; warnings are collected and surfaced.
  def enqueue_templates(templates, end_date)
    count    = 0
    warnings = []

    templates.each do |t|
      t.trigger_end_date = end_date
      violations = ValidationRuleEvaluator.call(record: t, entity: current_user.entity)

      if violations.select(&:blocker?).any?
        # Log blocker violations but do not halt the entire batch — skip this template.
        Rails.logger.warn("[FundRatioRunTemplates] Skipped '#{t.name}': #{violations.select(&:blocker?).map(&:message).join("; ")}")
        next
      end

      warnings.concat(violations.select(&:warning?).map { |v| "#{t.name}: #{v.message}" })
      t.enqueue(end_date: end_date, user_id: current_user.id)
      count += 1
    end

    [count, warnings]
  end

  # Returns a Date or nil — never raises so the controller can give a clean error.
  def parse_end_date(raw)
    raw.present? ? Date.local_parse(raw) : nil
  rescue ArgumentError
    nil
  end

  # Select2 submits portfolio_companies_tags as an array; join to comma-separated string for storage.
  def coerce_portfolio_companies_tags
    p = params[:fund_ratio_run_template]
    return unless p&.key?(:portfolio_companies_tags)
    p[:portfolio_companies_tags] = Array(p[:portfolio_companies_tags]).map(&:strip).reject(&:blank?).join(",")
  end

  def template_params
    params.require(:fund_ratio_run_template).permit(
      :name, :anchor_fund_id, :portfolio_companies_tags, :position,
      fund_ids: [], portfolio_company_ids: [], sectors: [], tags: []
    )
  end
end
