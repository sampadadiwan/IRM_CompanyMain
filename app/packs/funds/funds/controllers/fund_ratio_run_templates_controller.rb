# Manages FundRatioRunTemplate records and their trigger actions.
#
# trigger_all / trigger_by_tag enqueue one FundRatioRunTemplateBatchJob so
# matched templates run sequentially (not concurrently). trigger_one enqueues
# FundRatiosScenarioJob directly. None of these actions mutate template records.
class FundRatioRunTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy trigger_one runs]
  before_action :coerce_portfolio_companies_tags, only: %i[create update]
  after_action  :verify_authorized

  # GET /fund_ratio_run_templates
  def index
    authorize FundRatioRunTemplate
    # All entity-scoped templates ordered by position then name.
    # distinct_tags is used to populate the "Run by Tag" dropdown.
    @templates = policy_scope(FundRatioRunTemplate).ordered
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

  # GET /fund_ratio_run_templates/:id
  def show
    authorize @template
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
  # Enqueues a single FundRatioRunTemplateBatchJob that runs every entity template
  # sequentially — templates execute one after another, not concurrently.
  def trigger_all
    authorize FundRatioRunTemplate, :trigger?
    end_date = parse_end_date(params[:end_date])
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?

    templates  = policy_scope(FundRatioRunTemplate).ordered
    valid_ids  = collect_valid_ids(templates, end_date)
    FundRatioRunTemplateBatchJob.perform_later(valid_ids, end_date, current_user.id) if valid_ids.any?
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued #{valid_ids.size} ratio #{'calculation'.pluralize(valid_ids.size)} for #{end_date} — running sequentially."
  end

  # POST /fund_ratio_run_templates/trigger_by_tag
  # Enqueues a single FundRatioRunTemplateBatchJob for templates matching the tag,
  # running them sequentially.
  def trigger_by_tag
    authorize FundRatioRunTemplate, :trigger?
    end_date = parse_end_date(params[:end_date])
    tag      = params[:tag].to_s.strip
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "end_date is required" if end_date.nil?
    return redirect_back_or_to(fund_ratio_run_templates_path), alert: "tag is required"      if tag.blank?

    templates  = policy_scope(FundRatioRunTemplate).for_tag(tag).ordered
    valid_ids  = collect_valid_ids(templates, end_date)
    FundRatioRunTemplateBatchJob.perform_later(valid_ids, end_date, current_user.id) if valid_ids.any?
    redirect_to fund_ratio_run_templates_path,
                notice: "Enqueued #{valid_ids.size} ratio #{'calculation'.pluralize(valid_ids.size)} for tag '#{tag}' on #{end_date} — running sequentially."
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
                         alert: "Cannot enqueue '#{@template.name}': #{blockers.map(&:message).join('; ')}"
    end

    @template.enqueue(end_date: end_date, user_id: current_user.id)
    redirect_to fund_ratio_run_templates_path, notice: "Enqueued '#{@template.name}' for #{end_date}."
  end

  private

  def set_template
    @template = FundRatioRunTemplate.find(params[:id])
  end

  # Validates each template and returns IDs of those that pass (no blockers).
  # Templates with blocker violations are skipped and logged; the rest are
  # returned in the same order they were supplied so position-based sequencing
  # is preserved when passed to FundRatioRunTemplateBatchJob.
  def collect_valid_ids(templates, end_date)
    templates.each_with_object([]) do |t, ids|
      t.trigger_end_date = end_date
      violations = ValidationRuleEvaluator.call(record: t, entity: current_user.entity)

      if violations.any?(&:blocker?)
        Rails.logger.warn("[FundRatioRunTemplates] Skipped '#{t.name}': #{violations.select(&:blocker?).map(&:message).join('; ')}")
        next
      end

      ids << t.id
    end
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

    p[:portfolio_companies_tags] = Array(p[:portfolio_companies_tags]).map(&:strip).compact_blank.join(",")
  end

  def template_params
    params.require(:fund_ratio_run_template).permit(
      :name, :anchor_fund_id, :portfolio_companies_tags, :position,
      fund_ids: [], portfolio_company_ids: [], sectors: [], tags: []
    )
  end
end
