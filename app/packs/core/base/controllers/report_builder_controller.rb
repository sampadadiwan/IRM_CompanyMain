class ReportBuilderController < ApplicationController
  before_action :set_report, only: %i[
    edit preview download update_template
    add_column remove_column update_column_label
    add_join remove_join
    update_aggregate update_sort update_name
    update_pivot update_view_settings update_schedule
    add_formula remove_formula validate_formula
    view apply_template
    wizard_step wizard_add_filter wizard_remove_filter
  ]

  WIZARD_STEPS = %w[columns joins aggregates filters sort review].freeze

  # Icon + example question shown on each root-model card in wizard step 1.
  # Purely cosmetic — any model not listed here still works, it just falls
  # back to a plain table icon and no example text.
  WIZARD_MODEL_META = {
    "Investor" => { icon: "ti-users", example: "Which LPs still have KYC pending?" },
    "Fund" => { icon: "ti-building-bank", example: "How much has each fund called vs. collected?" },
    "InvestorKyc" => { icon: "ti-shield-check", example: "Who is flagged for AML review?" },
    "CapitalCommitment" => { icon: "ti-file-text", example: "List every commitment with its called amount." },
    "CapitalCall" => { icon: "ti-phone-outgoing", example: "Which calls are still short of their due amount?" },
    "CapitalRemittance" => { icon: "ti-cash", example: "Which remittances are still pending?" },
    "CapitalRemittancePayment" => { icon: "ti-receipt-2", example: nil },
    "CapitalDistributionPayment" => { icon: "ti-arrow-back-up", example: "How much fee was deducted from each distribution?" },
    "CapitalDistribution" => { icon: "ti-cash-banknote", example: nil },
    "PortfolioInvestment" => { icon: "ti-briefcase", example: nil },
    "AggregatePortfolioInvestment" => { icon: "ti-chart-pie", example: nil },
    "AccountEntry" => { icon: "ti-book-2", example: nil },
    "FundUnit" => { icon: "ti-chart-bar", example: nil },
    "CommitmentAdjustment" => { icon: "ti-adjustments", example: nil },
    "ExchangeRate" => { icon: "ti-currency-dollar", example: nil },
    "KpiReport" => { icon: "ti-report", example: nil },
    "Kpi" => { icon: "ti-chart-line", example: nil },
    "Document" => { icon: "ti-file", example: nil }
  }.freeze
  WIZARD_DEFAULT_ICON = "ti-table".freeze

  # Acronyms `.underscore.humanize` can't know about (it just title-cases the
  # first word) — "Investor kyc" reads oddly next to "Investor KYC".
  WIZARD_LABEL_ACRONYMS = { "Kyc" => "KYC", "Kpi" => "KPI", "Aml" => "AML" }.freeze

  # Plain-language explanation + a tiny worked example for each way of
  # combining several related rows into one value — shown as tooltips next to
  # the aggregate picker on the wizard's "Summarize" step.
  WIZARD_AGGREGATE_HELP = {
    "sum" => { label: "Sum", blurb: "Adds every value together.", example: "3 commitments of ₹10L, ₹20L, ₹5L → ₹35L" },
    "count" => { label: "Count", blurb: "Counts how many rows there are — the column itself doesn't matter.", example: "3 commitments → 3" },
    "avg" => { label: "Average", blurb: "The arithmetic mean of the values.", example: "₹10L, ₹20L, ₹5L → ₹11.7L" },
    "min" => { label: "Minimum", blurb: "The smallest value.", example: "Commitment dates → the earliest one" },
    "max" => { label: "Maximum", blurb: "The largest value.", example: "Call due dates → the most recent one" },
    "latest" => { label: "Latest", blurb: "The value from the single most recent row.", example: "3 KYC records → the newest one's status" },
    "list" => { label: "List", blurb: "A comma-separated list of every distinct value.", example: "Unit types → \"Class A, Class B\"" }
  }.freeze

  # GET /report_builder/models
  def models
    authorize Report, :index?
    roots = ReportBuilderModelDiscovery.roots
    render json: roots.map { |m|
      {
        name: m.name,
        label: m.name.humanize,
        pack: ReportBuilderModelDiscovery.pack_for(m),
        columns: columns_for_model(m)
      }
    }
  end

  # GET /report_builder/associations?model=Investor
  def associations
    authorize Report, :index?
    model_name = params[:model].to_s.strip
    klass = ReportBuilderModelDiscovery.all_models.find { |m| m.name == model_name }
    return render json: { error: "Unknown model" }, status: :unprocessable_entity unless klass

    render json: ReportBuilderModelDiscovery.associations_for(klass, entity: current_user.entity)
  end

  # GET /report_builder/new
  def new
    authorize Report.new(entity: current_user.entity), :create?
    @bread_crumbs = { Reports: reports_path, 'New Report Builder': nil }
    @root_models = ReportBuilderModelDiscovery.roots.group_by { |m| ReportBuilderModelDiscovery.pack_for(m) }
  end

  # POST /report_builder
  def create
    name = params[:name].to_s.strip.presence || "Untitled Report"

    @report = Report.new(
      user: current_user,
      entity: current_user.entity,
      curr_role: current_user.curr_role,
      name: name,
      report_builder: true,
      url: "/report_builder",
      template: {
        version: 1,
        root_model: params[:root_model],
        joins: [],
        aggregates: {},
        root_filters: {},
        sort: {}
      }
    )
    authorize @report, :create?

    if @report.save
      redirect_to edit_report_builder_path(@report)
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /report_builder/wizard — step 1 of the guided wizard: name the report
  # and pick a root model, presented as a searchable grid of cards (grouped by
  # pack) instead of the plain dropdown on the advanced "New Report" page.
  def wizard_new
    authorize Report.new(entity: current_user.entity), :create?
    @bread_crumbs = { Reports: reports_path, 'Guided Report Wizard': nil }
    @root_models = ReportBuilderModelDiscovery.roots.group_by { |m| ReportBuilderModelDiscovery.pack_for(m) }
    render "report_builder/wizard/new"
  end

  # POST /report_builder/wizard — creates the Report exactly like #create,
  # then sends the user into step 2 of the wizard instead of the advanced
  # builder page.
  def wizard_create
    name = params[:name].to_s.strip.presence || "Untitled Report"

    @report = Report.new(
      user: current_user,
      entity: current_user.entity,
      curr_role: current_user.curr_role,
      name: name,
      report_builder: true,
      url: "/report_builder",
      template: {
        version: 1,
        root_model: params[:root_model],
        joins: [],
        aggregates: {},
        root_filters: {},
        sort: {}
      }
    )
    authorize @report, :create?

    if @report.save
      redirect_to wizard_report_builder_step_path(@report, step: "columns")
    else
      redirect_to wizard_report_builder_path, alert: @report.errors.full_messages.to_sentence
    end
  end

  # GET /report_builder/:id/wizard/:step — steps: columns, joins, aggregates,
  # filters, sort, review. Each step reuses the exact same data (@config,
  # columns_for_model, associations_for) and the exact same mutation actions
  # (add_column, add_join, update_aggregate, wizard_add_filter, update_sort)
  # as the advanced builder — the wizard is a friendlier front door onto the
  # same Report#template, not a second implementation of it.
  def wizard_step
    authorize @report, :update?

    step = params[:step].to_s
    return redirect_to wizard_report_builder_step_path(@report, step: "columns") unless WIZARD_STEPS.include?(step)

    @config     = ReportBuilderConfig.new(@report.template)
    @root_class = begin
      @config.root_class
    rescue StandardError
      nil
    end
    return redirect_to wizard_report_builder_path, alert: "That report's root model could not be loaded." unless @root_class

    # No joins configured yet — the aggregates step has nothing to show, so
    # skip straight past it rather than presenting an empty page.
    return redirect_to wizard_report_builder_step_path(@report, step: "filters") if step == "aggregates" && @config.joins.empty?

    @bread_crumbs = { Reports: reports_path, @report.name => view_report_builder_path(@report), 'Guided Wizard': nil }
    @root_columns = columns_for_model(@root_class)
    @associations = ReportBuilderModelDiscovery.associations_for(@root_class, entity: current_user.entity)

    ReportBuilderModelDiscovery.all_models

    @joined_columns = @config.joins.each_with_object({}) do |j, h|
      klass = j[:model].to_s.safe_constantize || ReportBuilderModelDiscovery.all_models.find { |m| m.name == j[:model].to_s }
      h[j[:relation].to_s] = columns_for_model(klass) if klass
    end

    @gvps = @report.grid_view_preferences.reorder(:sequence, :id).to_a

    render "report_builder/wizard/#{step}"
  end

  # POST /report_builder/:id/wizard_filter — a single plain-HTML-form filter
  # row (field + operator + value), for the wizard's filters step. Builds the
  # same Ransack predicate key ("field_op") the advanced builder's JS-driven
  # filter panel builds client-side, then merges it into the template exactly
  # like #update_template does — kept as a separate, tiny action only because
  # a no-JS form can't compose that composite key on its own.
  def wizard_add_filter
    authorize @report, :update?

    field = params[:field].to_s.strip
    op    = params[:op].to_s.strip.presence || "eq"
    value = params[:value].to_s.strip
    return redirect_to wizard_report_builder_step_path(@report, step: "filters") if field.blank?

    no_value_ops = %w[null not_null]
    pred_key = "#{field}_#{op}"
    pred_val = op == "in" ? value.split(",").map(&:strip).compact_blank : value
    pred_val = "1" if no_value_ops.include?(op)

    tmpl = (@report.template || {}).deep_stringify_keys
    relation = params[:relation].to_s.strip

    if relation.blank?
      filters = tmpl["root_filters"] || {}
      filters[pred_key] = pred_val
      @report.update!(template: tmpl.merge("root_filters" => filters))
    else
      joins = (tmpl["joins"] || []).map do |j|
        next j unless j["relation"] == relation

        child_filters = j["child_filters"] || {}
        child_filters[pred_key] = pred_val
        j.merge("child_filters" => child_filters)
      end
      @report.update!(template: tmpl.merge("joins" => joins))
    end

    redirect_to wizard_report_builder_step_path(@report, step: "filters")
  end

  # DELETE /report_builder/:id/wizard_filter — removes one filter predicate
  # added above, by its exact key (and relation, for a child filter).
  def wizard_remove_filter
    authorize @report, :update?

    pred_key = params[:pred_key].to_s
    relation = params[:relation].to_s.strip
    tmpl     = (@report.template || {}).deep_stringify_keys

    if relation.blank?
      filters = (tmpl["root_filters"] || {}).except(pred_key)
      @report.update!(template: tmpl.merge("root_filters" => filters))
    else
      joins = (tmpl["joins"] || []).map do |j|
        next j unless j["relation"] == relation

        j.merge("child_filters" => (j["child_filters"] || {}).except(pred_key))
      end
      @report.update!(template: tmpl.merge("joins" => joins))
    end

    redirect_to wizard_report_builder_step_path(@report, step: "filters")
  end

  # GET /report_builder/:id/edit
  def edit
    authorize @report, :update?
    @bread_crumbs = { Reports: reports_path, @report.name => view_report_builder_path(@report), Edit: nil }
    @config     = ReportBuilderConfig.new(@report.template)
    @root_class = begin
      @config.root_class
    rescue StandardError
      nil
    end

    return unless @root_class

    @root_columns   = columns_for_model(@root_class)
    @associations   = ReportBuilderModelDiscovery.associations_for(@root_class, entity: current_user.entity)

    # Ensure all models are loaded so constantize works for joined models
    ReportBuilderModelDiscovery.all_models

    @joined_columns = @config.joins.each_with_object({}) do |j, h|
      model_name = j[:model].to_s
      klass = model_name.safe_constantize

      # Fallback: search all models if safe_constantize failed
      klass = ReportBuilderModelDiscovery.all_models.find { |m| m.name == model_name } if klass.nil?

      if klass
        h[j[:relation].to_s] = columns_for_model(klass)
      else
        Rails.logger.warn "[ReportBuilder] Could not constantize model: #{model_name} for relation: #{j[:relation]}"
      end
    end
  end

  # GET /report_builder/:id/view
  def view
    authorize @report, :show?
    @bread_crumbs = { Reports: reports_path, @report.name => nil }

    engine = ReportBuilderQueryEngine.new(
      report: @report,
      entity: current_user.entity,
      external_filters: params[:q]
    )

    # Report-builder roots include large production tables (AccountEntry,
    # CapitalDistributionPayment, CapitalRemittance, Document, ...) — rendering
    # every matching row on one HTML page is exactly the kind of accidental
    # full-table materialization that's caused memory incidents before.
    # Paginate here the same way Pagy is used elsewhere in the app; @total
    # comes from a cheap COUNT query, not from loading the rows.
    @total   = engine.count
    per_page = (params[:per_page].presence || 100).to_i
    per_page = 100 unless per_page.positive?

    # Pagy raises (VariableError/OverflowError) for a page outside 1..total_pages
    # instead of clamping — clamp ourselves so a stale bookmarked page, a filter
    # change that shrinks @total, or a garbage ?page= param 500s instead of
    # just showing the nearest valid page.
    total_pages = @total.zero? ? 1 : (@total.to_f / per_page).ceil
    page_num    = (params[:page].presence || 1).to_i.clamp(1, total_pages)

    @pagy = Pagy.new(count: @total, page: page_num, items: per_page)
    limit = @pagy.respond_to?(:limit) ? @pagy.limit : @pagy.vars[:items]

    @rows    = engine.run(limit: limit, offset: @pagy.offset)
    @columns = engine.columns

    # Mimic standard index variables
    @q = @report.root_class.ransack(params[:q])
    @search_predicate = default_search_predicate(@report)

    render :view
  end

  # GET /report_builder/:id/preview
  def preview
    authorize @report, :show?

    engine   = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity, external_filters: params[:q])
    @rows    = engine.run(limit: 20)
    @columns = engine.columns
    @total   = engine.count

    respond_to do |format|
      format.html { render partial: "report_builder/preview_table" }
      format.json { render json: { rows: @rows, columns: @columns.map { |c| { key: c.key, label: c.label || c.name } }, total: @total } }
    end
  rescue StandardError => e
    respond_to do |format|
      format.html { render inline: "<%= turbo_frame_tag 'report_builder_preview' do %><div class='alert alert-danger m-3'>#{ERB::Util.html_escape(e.message)}</div><% end %>" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  # GET /report_builder/:id/download
  def download
    authorize @report, :show?

    ReportBuilderExportJob.perform_later(@report.id, current_user.id)

    redirect_back_or_to(edit_report_builder_path(@report), notice: "Report generation started. You will be notified when it's ready.")
  rescue StandardError => e
    redirect_back_or_to(edit_report_builder_path(@report), alert: "Failed to start export: #{e.message}")
  end

  # PATCH /report_builder/:id/template
  def update_template
    authorize @report, :update?

    existing = (@report.template || {}).deep_stringify_keys
    delta    = (params[:template] || {}).to_unsafe_h.deep_stringify_keys
    merged   = deep_merge(existing, delta)

    if @report.update(template: merged)
      render json: { ok: true }
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /report_builder/:id/columns
  def add_column
    authorize @report, :update?

    key = params[:key].to_s
    unless column_key_allowed?(key)
      return redirect_to edit_report_builder_path(@report),
                         alert: "Column '#{key}' is not a valid column for this report."
    end

    name = params[:name].presence || key.split(".").last.humanize
    unless @report.grid_view_preferences.exists?(key: key)
      # Get the next sequence number
      max_seq = @report.grid_view_preferences.maximum(:sequence) || 0
      @report.grid_view_preferences.create!(
        key: key,
        name: name,
        label: params[:label].presence || name,
        entity_id: @report.entity_id,
        sequence: max_seq + 1
      )
    end

    redirect_back_or_to edit_report_builder_path(@report)
  end

  # DELETE /report_builder/:id/columns/:gvp_id
  def remove_column
    authorize @report, :update?
    @report.grid_view_preferences.find(params[:gvp_id]).destroy
    redirect_back_or_to edit_report_builder_path(@report)
  end

  # PATCH /report_builder/:id/columns/:gvp_id — overrides a column's display
  # label (the header text shown in preview/export). Falls back to the
  # original default label when left blank rather than saving an empty one.
  def update_column_label
    authorize @report, :update?

    gvp = @report.grid_view_preferences.find(params[:gvp_id])
    label = params[:label].to_s.strip
    gvp.update!(label: label.presence || gvp.name)

    redirect_back_or_to edit_report_builder_path(@report)
  end

  # POST /report_builder/:id/join
  def add_join
    authorize @report, :update?

    relation = params[:relation].to_s.strip
    model    = params[:model].to_s.strip
    fk       = params[:fk].to_s.strip

    return redirect_to edit_report_builder_path(@report) if relation.blank?

    tmpl  = (@report.template || {}).deep_stringify_keys
    joins = tmpl["joins"] || []

    unless joins.any? { |j| j["relation"] == relation }
      joins << { "relation" => relation, "model" => model, "fk" => fk }
      @report.update!(template: tmpl.merge("joins" => joins))
    end

    redirect_back_or_to edit_report_builder_path(@report)
  end

  # DELETE /report_builder/:id/join
  def remove_join
    authorize @report, :update?

    relation = params[:relation].to_s
    tmpl     = (@report.template || {}).deep_stringify_keys
    joins      = (tmpl["joins"] || []).reject { |j| j["relation"] == relation }
    aggregates = (tmpl["aggregates"] || {}).reject { |k, _| k.start_with?("#{relation}.") }

    @report.grid_view_preferences.where("`key` LIKE ?", "#{relation}.%").destroy_all
    @report.update!(template: tmpl.merge("joins" => joins, "aggregates" => aggregates))

    redirect_back_or_to edit_report_builder_path(@report)
  end

  # PATCH /report_builder/:id/aggregate
  def update_aggregate
    authorize @report, :update?

    key = params[:key].to_s.split(";").first.strip
    agg = params[:aggregate].presence

    tmpl       = (@report.template || {}).deep_stringify_keys
    aggregates = tmpl["aggregates"] || {}
    agg ? aggregates[key] = agg : aggregates.delete(key)

    @report.update!(template: tmpl.merge("aggregates" => aggregates))

    respond_to do |format|
      # The advanced builder's JS drives this via fetch (JSON); the wizard's
      # "Summarize" step uses a plain HTML form (no JS) and expects a redirect
      # back to wherever it was submitted from.
      format.html { redirect_back_or_to edit_report_builder_path(@report) }
      format.json { render json: { ok: true } }
    end
  end

  # PATCH /report_builder/:id/sort
  def update_sort
    authorize @report, :update?

    tmpl = (@report.template || {}).deep_stringify_keys
    @report.update!(template: tmpl.merge("sort" => { "key" => params[:sort_key], "dir" => params[:sort_dir] }))

    respond_to do |format|
      format.html do
        # The wizard's Sort step folds "save" into its "Continue" button
        # (no separate Save step) — it passes where to go next; anything
        # else (the advanced builder's non-JS fallback) just returns here.
        if params[:wizard_next_step].present?
          redirect_to wizard_report_builder_step_path(@report, step: params[:wizard_next_step])
        else
          redirect_back_or_to edit_report_builder_path(@report)
        end
      end
      format.json { render json: { ok: true } }
    end
  end

  # PATCH /report_builder/:id/name
  def update_name
    authorize @report, :update?

    if @report.update(name: params[:name].to_s.strip.presence || "Untitled Report")
      render json: { ok: true, name: @report.name }
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /report_builder/:id/pivot
  def update_pivot
    authorize @report, :update?

    relation = params[:relation].to_s.strip
    return redirect_to edit_report_builder_path(@report) if relation.blank?

    tmpl = (@report.template || {}).deep_stringify_keys
    activating_pivot = params[:clear].blank?
    joins = (tmpl["joins"] || []).map do |j|
      if j["relation"] == relation
        if activating_pivot
          j.merge("pivot" => {
                    "group_bys" => Array(params[:group_bys]).map { |x| x.to_s.strip }.compact_blank,
                    "value_col" => params[:value_col].to_s.strip,
                    "aggregate" => params[:aggregate].to_s.strip.presence || "sum"
                  })
        else
          j.except("pivot")
        end
      else
        j
      end
    end

    # A pivot config takes over the whole relation (the query engine's pass2
    # runs either the pivot aggregator OR the regular one per join, never
    # both — see ReportBuilderQueryEngine#pass2). Any individually-selected
    # columns for this relation from before switching to pivot mode would
    # otherwise sit there orphaned, rendering blank in every row.
    @report.grid_view_preferences.where("`key` LIKE ?", "#{relation}.%").destroy_all if activating_pivot

    @report.update!(template: tmpl.merge("joins" => joins))
    redirect_back_or_to edit_report_builder_path(@report)
  end

  # PATCH /report_builder/:id/view_settings
  def update_view_settings
    authorize @report, :update?

    if @report.update(params.permit(:is_view, :view_target, :shared))
      render json: { ok: true }
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /report_builder/:id/schedule
  def update_schedule
    authorize @report, :update?

    schedule = @report.report_schedule || @report.build_report_schedule

    # Handle recipients as array
    recipients = params[:recipients].to_s.split(",").map(&:strip).compact_blank

    if schedule.update(
      frequency: params[:frequency],
      recipients: recipients,
      enabled: params[:enabled] == "true"
    )
      render json: { ok: true }
    else
      render json: { errors: schedule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /report_builder/:id/formulas
  def add_formula
    authorize @report, :update?

    expression = params[:expression].to_s
    allowed_keys = @report.grid_view_preferences.pluck(:key).to_set { |k| k.split(";").first.strip }
    referenced   = expression.scan(/\[([^\]]+)\]/).flatten.map { |r| r.split(";").first.strip }
    bad          = referenced.reject { |r| allowed_keys.include?(r) }

    if bad.any?
      return redirect_to edit_report_builder_path(@report),
                         alert: "Formula references unknown column(s): #{bad.join(', ')}"
    end

    tmpl = (@report.template || {}).deep_stringify_keys
    formulas = tmpl["formulas"] || []

    formulas << {
      "key" => "formula_#{Time.now.to_i}",
      "label" => params[:label].presence || "New Formula",
      "expression" => expression
    }

    @report.update!(template: tmpl.merge("formulas" => formulas))
    redirect_back_or_to edit_report_builder_path(@report)
  end

  # DELETE /report_builder/:id/formulas/:key
  def remove_formula
    authorize @report, :update?

    tmpl = (@report.template || {}).deep_stringify_keys
    formulas = (tmpl["formulas"] || []).reject { |f| f["key"] == params[:key] }

    @report.update!(template: tmpl.merge("formulas" => formulas))
    redirect_back_or_to edit_report_builder_path(@report)
  end

  # POST /report_builder/:id/validate_formula
  def validate_formula
    authorize @report, :update?

    expression = params[:expression].to_s

    # Extract all [column.key] references from the expression and validate
    # them against the columns actually selected in this report.
    allowed_keys = @report.grid_view_preferences.pluck(:key).to_set { |k| k.split(";").first.strip }

    referenced = expression.scan(/\[([^\]]+)\]/).flatten.map { |r| r.split(";").first.strip }
    bad = referenced.reject { |r| allowed_keys.include?(r) }
    return render json: { ok: false, error: "Unknown column(s): #{bad.join(', ')}. Only selected report columns can be used in formulas." } if bad.any?

    engine = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity)
    sample_row = engine.run(limit: 1).first || {}
    sample_row = referenced.index_with(0) if sample_row.empty?

    result = ReportBuilderFormulaService.validate(expression, sample_row)

    if result == true
      render json: { ok: true }
    else
      render json: { ok: false, error: result }
    end
  end

  # POST /report_builder/:id/apply_template
  def apply_template
    authorize @report, :update?

    template_key = params[:template_key]
    template_config = report_templates[template_key]

    if template_config
      # Clear existing GVPs
      @report.grid_view_preferences.destroy_all

      # Update template JSON
      @report.update!(template: template_config[:template].deep_stringify_keys)

      # Create new GVPs
      template_config[:columns].each_with_index do |col, i|
        @report.grid_view_preferences.create!(
          key: col[:key],
          name: col[:name],
          label: col[:label],
          entity_id: @report.entity_id,
          sequence: i + 1
        )
      end

      redirect_back_or_to edit_report_builder_path(@report), notice: "Template '#{template_config[:name]}' applied."
    else
      redirect_back_or_to edit_report_builder_path(@report), alert: "Template not found."
    end
  end

  private

  def report_templates
    {
      "investor_commitment_summary" => {
        name: "Investor Commitment Summary",
        description: "Total committed and called amounts per investor.",
        template: {
          root_model: "Investor",
          joins: [
            { relation: "capital_commitments", model: "CapitalCommitment", include_zero_rows: true }
          ],
          aggregates: {
            "capital_commitments.amount" => "sum",
            "capital_commitments.called_amount" => "sum",
            "capital_commitments.id" => "count"
          }
        },
        columns: [
          { key: "investor_name", name: "Name", label: "Investor Name" },
          { key: "capital_commitments.amount; num-col", name: "Committed", label: "Total Committed" },
          { key: "capital_commitments.called_amount; num-col", name: "Called", label: "Total Called" },
          { key: "capital_commitments.id", name: "Count", label: "# Commitments" }
        ]
      },
      "kyc_audit" => {
        name: "KYC Compliance Audit",
        description: "Latest KYC status and verification dates for all investors.",
        template: {
          root_model: "Investor",
          joins: [
            { relation: "investor_kycs", model: "InvestorKyc", include_zero_rows: true }
          ],
          aggregates: {
            "investor_kycs.status" => "latest",
            "investor_kycs.verified_at" => "latest"
          }
        },
        columns: [
          { key: "investor_name", name: "Name", label: "Investor Name" },
          { key: "investor_kycs.status", name: "Status", label: "KYC Status" },
          { key: "investor_kycs.verified_at", name: "Verified At", label: "Last Verified" }
        ]
      }
    }
  end
  helper_method :report_templates

  # Model class names are PascalCase with no underscores ("CapitalCommitment"),
  # so plain `.humanize` mangles them into one run-together word
  # ("Capitalcommitment") — humanize only inserts spacing at "_" boundaries.
  # `.underscore` first ("capital_commitment") gives humanize something it can
  # actually split ("Capital commitment"). Used anywhere a root/joined model
  # name is shown to the user.
  def wizard_model_label(model_name)
    label = model_name.to_s.underscore.humanize
    WIZARD_LABEL_ACRONYMS.reduce(label) { |l, (from, to)| l.gsub(/\b#{from}\b/, to) }
  end
  helper_method :wizard_model_label

  def wizard_icon_for(model_name)
    WIZARD_MODEL_META.dig(model_name.to_s, :icon) || WIZARD_DEFAULT_ICON
  end
  helper_method :wizard_icon_for

  # Icon for a single COLUMN (not a root model) — used in the wizard's column
  # pickers. The "; col-type" suffix convention (num-col/date-col/label-col)
  # only exists for STANDARD_COLUMNS-sourced entries; most of the columns on
  # the picker actually come from ransackable_attributes (see
  # columns_for_model below), which never carries that suffix — so relying on
  # it alone left almost every column defaulting to the generic "Abc" icon
  # regardless of its real type. Falls back to the actual DB column's type via
  # Report#model_columns_hash, which already resolves both root and joined
  # ("relation.field") keys.
  def wizard_type_icon_for(raw_key)
    key = raw_key.to_s
    return "ti-hash" if key.include?("num-col")
    return "ti-calendar" if key.include?("date-col")
    return "ti-tag" if key.include?("label-col")

    clean_key = key.split(";").first.strip
    column = @report&.model_columns_hash&.[](clean_key)
    case column&.type
    when :integer, :decimal, :float then "ti-hash"
    when :date, :datetime then "ti-calendar"
    when :boolean then "ti-toggle-left"
    else "ti-abc"
    end
  rescue StandardError
    "ti-abc"
  end
  helper_method :wizard_type_icon_for

  def wizard_example_for(model_name)
    WIZARD_MODEL_META.dig(model_name.to_s, :example)
  end
  helper_method :wizard_example_for

  def wizard_aggregate_help
    WIZARD_AGGREGATE_HELP
  end
  helper_method :wizard_aggregate_help

  def set_report
    @report = Report.find(params[:id])
  end

  # Picks a sensible default Ransack "_cont" predicate for the quick-search
  # box on the view page — the first selected string column on the root
  # model, falling back to any string column on the root model.
  def default_search_predicate(report)
    root_class = report.root_class
    columns_hash = root_class.columns_hash

    candidate = report.grid_view_preferences
                      .order(:sequence)
                      .pluck(:key)
                      .map { |k| k.split(";").first.strip }
                      .find { |k| k.exclude?(".") && columns_hash[k]&.type == :string }

    candidate ||= root_class.column_names.find { |c| columns_hash[c].type == :string }
    candidate ? "#{candidate}_cont" : nil
  rescue StandardError
    nil
  end

  # Rejects any column key that doesn't resolve to a real, allowed column on
  # the root model (or on a model reachable via an actual association chain
  # from a configured join). This is the boundary that keeps GridViewPreference
  # keys safe to later use in QueryEngine#merge (root.send(...)) and in raw
  # SQL identifier interpolation (ChildAggregator/PivotAggregator).
  def column_key_allowed?(key)
    clean = key.to_s.split(";").first.strip
    return false if clean.blank?

    config = ReportBuilderConfig.new(@report.template)
    return false unless config.valid?

    if clean.include?(".")
      parts         = clean.split(".")
      field         = parts.pop
      relation_path = parts.join(".")

      klass = resolve_join_klass(config.root_class, relation_path)
      return false unless klass

      columns_for_model(klass).any? { |c| c[:key] == field }
    else
      columns_for_model(config.root_class).any? { |c| c[:key] == clean }
    end
  rescue StandardError
    false
  end

  # Walks real AR reflections from the root class along a dotted relation
  # path (e.g. "capital_commitments.fund") so a key can only be allowed if it
  # corresponds to an actual declared association — never an arbitrary string.
  def resolve_join_klass(root_class, relation_path)
    klass = root_class
    relation_path.to_s.split(".").each do |part|
      reflection = klass.reflect_on_association(part.to_sym)
      return nil unless reflection

      klass = reflection.klass
    end
    klass
  end

  def deep_merge(base, delta)
    delta.each_with_object(base.dup) do |(k, v), acc|
      acc[k] = acc[k].is_a?(Hash) && v.is_a?(Hash) ? deep_merge(acc[k], v) : v
    end
  end

  def columns_for_model(klass)
    return [] unless klass

    # Use a Hash to ensure uniqueness by key
    cols_by_key = {}

    # 1. Ransackable attributes (requested by user for filters)
    if klass.respond_to?(:ransackable_attributes)
      klass.ransackable_attributes.each do |attr|
        cols_by_key[attr] = { label: attr.humanize, key: attr }
      end
    end

    # 2. Standard Columns (overlay to get nice labels/types)
    if klass.const_defined?(:STANDARD_COLUMNS)
      klass.const_get(:STANDARD_COLUMNS).each do |label, key|
        clean_key = key.to_s.split(";").first.strip
        cols_by_key[clean_key] = { label: label, key: key }
      end
    end

    # 3. Additional Columns
    if klass.const_defined?(:ADDITIONAL_COLUMNS)
      klass.const_get(:ADDITIONAL_COLUMNS).each do |label, key|
        clean_key = key.to_s.split(";").first.strip
        cols_by_key[clean_key] = { label: label, key: key }
      end
    end

    # 4. Fallback to DB columns if still empty
    if cols_by_key.empty?
      klass.column_names.each do |name|
        next if %w[id entity_id created_at updated_at deleted_at].include?(name)

        cols_by_key[name] = { label: name.humanize, key: name }
      end
    end

    cols_by_key.values.map do |c|
      {
        label: c[:label].to_s.split(";").first.strip,
        key: c[:key].to_s.split(";").first.strip,
        raw_key: c[:key],
        raw_label: c[:label]
      }
    end.sort_by { |c| c[:label] }
  end
end
