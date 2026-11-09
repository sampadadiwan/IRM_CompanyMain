class ReportBuilderController < ApplicationController
  include ReportBuilder::BuilderUpdates
  include ReportBuilder::Wizard
  include ReportBuilder::Starting
  include ReportBuilder::Delivery
  include ReportBuilder::Assistant

  before_action :set_report, only: %i[
    edit preview download update_template
    add_column remove_column update_column_label
    add_join remove_join
    update_aggregate update_sort update_name
    update_pivot update_join_settings update_schedule schedule_check schedule_test move_column filter_row pivot_preview
    add_formula remove_formula validate_formula undo
    view duplicate
    draft draft_state draft_refine draft_fund draft_chart draft_describe_chart draft_save draft_discard
    wizard_step wizard_add_filter wizard_remove_filter
  ]

  # Any other change ends the chance to undo a removal (ReportBuilderUndo).
  # After the action, so a refused request (another entity) never touches it.
  after_action :drop_undo, only: %i[
    update_template add_column update_column_label add_join update_aggregate update_sort
    update_pivot update_join_settings move_column add_formula remove_formula
  ]

  # Rows shown in the builder's preview (P4: the page copy says the same number)
  PREVIEW_LIMIT = 20

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
    @bread_crumbs = { Reports: reports_path, 'New report': nil }
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

  # GET /report_builder/:id/edit
  def edit
    authorize @report, :update?
    @bread_crumbs = { Reports: reports_path, @report.name => view_report_builder_path(@report), Edit: nil }
    load_builder_state
  end

  # GET /report_builder/:id/view
  def view
    authorize @report, :show?
    @bread_crumbs = { Reports: reports_path, @report.name => nil }

    # Narrow down's Apply: its field / operator / value become one more `q`
    # filter, in a clean address that can be bookmarked (delivery H10)
    return redirect_to(view_report_builder_path(@report, narrowed_params)) if params[:apply].present? && params[:nf].present?

    # The reader's own filters for this visit: only on the report's filter
    # fields, never over a filter the report sets itself (H10, E9, E10)
    @config = ReportBuilderConfig.new(@report.template)
    @reader_filters = ReportBuilderReaderFilters.new(config: @config, entity: current_user.entity, q: params[:q])

    # A clicked column header sorts this visit only; the engine ignores a key
    # that isn't one of the report's columns (H20, X4). M16 — the rows the
    # viewer may see (their Pundit scope of the root and of each join)
    engine = ReportBuilderQueryEngine.new(
      report: @report,
      entity: current_user.entity,
      user: current_user,
      external_filters: @reader_filters.applied,
      sort_override: params[:sort].present? ? { key: params[:sort].to_s, dir: params[:dir].to_s } : nil
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

    # Pagy 9 takes `limit:` (it ignores the old `items:`), so per_page really applies (E18)
    @pagy = Pagy.new(count: @total, page: page_num, limit: per_page)
    limit = @pagy.respond_to?(:limit) ? @pagy.limit : @pagy.vars[:items]

    @rows    = engine.run(limit: limit, offset: @pagy.offset)
    @columns = engine.columns

    # One formatter and one totals row for every place the report is shown;
    # the totals cover the rows on screen and say so on a paged report (H17, E18)
    @formatter     = ReportBuilderValueFormatter.new(config: @config, entity: current_user.entity)
    @totals        = ReportBuilderTotals.new(rows: @rows, columns: @columns, config: @config,
                                             scope: @pagy.pages > 1 ? :page : :all)
    @sort          = engine.effective_sort
    @sort_capped   = engine.computed_sort_capped?

    # Mimic standard index variables
    @q = @report.root_class.ransack(@reader_filters.applied)

    render :view
  end

  # GET /report_builder/:id/preview
  def preview
    authorize @report, :show?

    # The builder's preview (20 rows) or the wizard's sample (limit=5)
    limit = params[:limit].presence ? params[:limit].to_i.clamp(1, PREVIEW_LIMIT) : PREVIEW_LIMIT
    load_preview_state(limit: limit)

    respond_to do |format|
      # An engine error is shown inside the preview frame, never as an error page (E19)
      format.html { render partial: "report_builder/preview_table", locals: { builder: params[:builder].present? } }
      format.json do
        if @preview_error
          render json: { error: @preview_error }, status: :unprocessable_entity
        else
          render json: { rows: @rows, columns: @columns.map { |c| { key: c.key, label: c.label || c.name } }, total: @total }
        end
      end
    end
  end

  # GET /report_builder/:id/download
  def download
    authorize @report, :show?

    ReportBuilderExportJob.perform_later(@report.id, current_user.id)
    # M11 D4 — a report export
    SecurityEvents.record("data.exported", user: current_user, details: { what: "report_builder#download", name: @report.name })

    respond_to do |format|
      # The Export button already reads "Preparing…" (set in the browser on click) and the
      # export job replaces it when the file is saved — nothing to send back (H1, H2)
      format.turbo_stream { render turbo_stream: [] }
      format.html { redirect_back_or_to(edit_report_builder_path(@report), notice: "Report generation started. You will be notified when it's ready.") }
    end
  rescue StandardError => e
    respond_to do |format|
      # The job couldn't even be queued: put the button back and say why (X1)
      format.turbo_stream do
        UserAlert.new(user_id: current_user.id, entity_id: current_user.entity_id, level: "danger",
                      message: "Couldn't export <strong>#{ERB::Util.h(@report.name)}</strong>: #{ERB::Util.h(e.message)}").broadcast
        size = params[:size].presence_in(%w[sm])
        render turbo_stream: turbo_stream.replace(["rb_export_#{@report.id}", size].compact.join("_"),
                                                  partial: "report_builder/export_button", locals: { report: @report, size: size })
      end
      format.html { redirect_back_or_to(edit_report_builder_path(@report), alert: "Failed to start export: #{e.message}") }
    end
  end

  # PATCH /report_builder/:id/template
  def update_template
    authorize @report, :update?

    existing = (@report.template || {}).deep_stringify_keys
    delta    = (params[:template] || {}).to_unsafe_h.deep_stringify_keys
    merged   = deep_merge(existing, delta)

    if @report.update(template: merged)
      return finish_change("Saved") if builder_request? || wizard_request?

      render json: { ok: true }
    else
      render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # POST /report_builder/:id/columns
  def add_column
    authorize @report, :update?

    # Several keys from the picker's "Add selected" (labels from the catalog),
    # or one key with an optional name (older callers). Worked examples H4, E2.
    bulk = params[:keys].present?
    keys = bulk ? Array(params[:keys]).map(&:to_s).compact_blank.uniq : [params[:key].to_s]

    present = @report.grid_view_preferences.pluck(:key).to_set { |k| k.split(";").first.strip }
    added   = []
    refused = []

    Report.transaction do
      # Each added column goes after the last; nothing else in the loop adds columns, so the current
      # maximum is read once and counted up rather than queried again for every key
      last_sequence = @report.grid_view_preferences.maximum(:sequence) || 0
      keys.each do |key|
        clean = key.split(";").first.strip
        # E2 — already in the report: skip quietly
        next if present.include?(clean)

        auto_join_for(clean)
        # E2 — not a column of this report: refuse, but keep adding the rest
        unless column_key_allowed?(key)
          refused << clean
          next
        end

        name = bulk ? ReportBuilderColumnCatalog.label_for(ReportBuilderConfig.new(@report.template), key) : (params[:name].presence || clean.split(".").last.humanize)
        last_sequence += 1
        @report.grid_view_preferences.create!(key: key, name: name, label: (bulk ? nil : params[:label].presence) || name,
                                              entity_id: @report.entity_id, sequence: last_sequence)
        store_default_aggregate(key)
        present << clean
        added << name
      end
    end

    if refused.any?
      message = "#{added.any? ? "Added #{added.to_sentence}. " : 'No columns added. '}" \
                "#{refused.map { |k| "'#{k}'" }.to_sentence} #{refused.size == 1 ? "isn't" : "aren't"} available in this report."
      return finish_change(message, level: :danger,
                                    fallback: -> { redirect_to edit_report_builder_path(@report), alert: message })
    end

    finish_change(added.size > 1 ? "Added #{added.size} columns" : "Added #{added.first || 'nothing new'}")
  end

  # DELETE /report_builder/:id/columns/:gvp_id
  def remove_column
    authorize @report, :update?
    gvp    = @report.grid_view_preferences.find(params[:gvp_id])
    before = (@report.template || {}).deep_dup
    label  = gvp.label.presence || gvp.name
    gvp.destroy
    # H11 — kept for 10 minutes so the toast's Undo can put it back
    token = ReportBuilderUndo.snapshot!(@report, label: label, before: before, removed: [gvp])
    finish_change("Removed #{label}", undo_token: token)
  end

  # POST /report_builder/:id/undo — puts back the last removal, within 10
  # minutes and only if nothing changed since. Worked examples H11, H12, E12, E13.
  def undo
    authorize @report, :update?

    outcome, detail = ReportBuilderUndo.restore!(@report, params[:token])
    return finish_change("Restored #{detail}") if outcome == :ok

    finish_change(detail, level: :danger, status: :unprocessable_entity,
                          fallback: -> { redirect_to edit_report_builder_path(@report), alert: detail })
  end

  # GET /report_builder/:id/pivot_preview — how many columns a pivot would
  # create and the first headers, before Apply. Worked examples H16, X2.
  def pivot_preview
    authorize @report, :update?

    engine = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity, user: current_user)
    result = engine.pivot_preview(params[:relation].to_s, Array(params[:group_bys]).compact_blank, params[:value_col].to_s)
    return render json: { error: result[:error] }, status: :unprocessable_entity if result[:error]

    render json: result.merge(warn_over: ReportBuilderHealthCheck::PIVOT_WARN_COLUMNS)
  end

  # GET /report_builder/:id/filter_row — one filter row drawn for a field (its
  # input and plain-word operators), fetched by the builder when a filter row
  # is added or its field / operator changes. Worked examples H7, H8.
  def filter_row
    authorize @report, :update?
    load_builder_state

    relation = params[:relation].presence
    columns  = relation ? (@joined_filter_columns || {})[relation] || [] : @root_filter_columns
    render partial: "report_builder/filter_row",
           locals: { scope: relation ? "child" : "root", relation: relation, field: params[:field].presence,
                     op: params[:op].presence, value: params[:value], columns: columns }
  end

  # PATCH /report_builder/:id/columns/:gvp_id/move — moves a column (or a
  # formula / pivot position) one place left or right. Sequences are renumbered
  # 1..n first, since removals leave gaps. Worked examples H6, E6, X3.
  def move_column
    authorize @report, :update?

    direction = params[:direction].to_s
    ordered   = @report.grid_view_preferences.reorder(:sequence, :id).to_a
    index     = ordered.index { |g| g.id == params[:gvp_id].to_i }
    raise ActiveRecord::RecordNotFound unless index

    target = { "left" => index - 1, "right" => index + 1 }[direction]
    # X3 / E6 — an unknown direction, or past either end
    if target.nil? || target.negative? || target >= ordered.size
      message = target.nil? ? "Columns move left or right only" : "That column is already at the end"
      return finish_change(message, level: :danger, status: :unprocessable_entity,
                                    fallback: -> { render json: { errors: [message] }, status: :unprocessable_entity })
    end

    ordered[index], ordered[target] = ordered[target], ordered[index]
    Report.transaction do
      ordered.each_with_index { |gvp, i| gvp.update_column(:sequence, i + 1) unless gvp.sequence == i + 1 }
    end
    @report.touch

    finish_change("Moved #{ordered[target].label.presence || ordered[target].name}")
  end

  # PATCH /report_builder/:id/columns/:gvp_id — overrides a column's display
  # label (the header text shown in preview/export). Falls back to the
  # original default label when left blank rather than saving an empty one.
  def update_column_label
    authorize @report, :update?

    gvp = @report.grid_view_preferences.find(params[:gvp_id])
    label = params[:label].to_s.strip
    gvp.update!(label: label.presence || gvp.name)

    finish_change("Renamed to #{gvp.label}")
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

    finish_change("Added #{relation.humanize}")
  end

  # DELETE /report_builder/:id/join
  def remove_join
    authorize @report, :update?

    relation = params[:relation].to_s
    tmpl     = (@report.template || {}).deep_stringify_keys
    joins      = (tmpl["joins"] || []).reject { |j| j["relation"] == relation }
    aggregates = (tmpl["aggregates"] || {}).reject { |k, _| k.start_with?("#{relation}.") }

    before  = tmpl.deep_dup
    columns = @report.grid_view_preferences.where("`key` LIKE ?", "#{relation}.%").to_a
    removed = columns + @report.grid_view_preferences.where(key: "pivot:#{relation}").to_a

    Report.transaction do
      columns.each(&:destroy)
      # Its pivot's position goes with it (E10)
      @report.grid_view_preferences.where(key: "pivot:#{relation}").delete_all
      @report.update!(template: tmpl.merge("joins" => joins, "aggregates" => aggregates))
    end

    # H12 — the join, its filters and its columns can be put back together
    label = "#{relation.humanize} and #{helpers.pluralize(columns.size, 'column')}"
    token = ReportBuilderUndo.snapshot!(@report, label: label, before: before, removed: removed)
    finish_change("Removed #{label}", undo_token: token)
  end

  # PATCH /report_builder/:id/aggregate
  def update_aggregate
    authorize @report, :update?

    key = params[:key].to_s.split(";").first.strip
    agg = params[:aggregate].presence

    # Only the totals the engine knows are accepted; anything else would be
    # silently ignored and leave the column blank (X2)
    if agg && ReportBuilderColumnType::AGGREGATES.exclude?(agg)
      message = "Unknown total '#{agg}'"
      return respond_to do |format|
        format.html { redirect_back_or_to edit_report_builder_path(@report), alert: message }
        format.json { render json: { errors: [message] }, status: :unprocessable_entity }
      end
    end

    tmpl       = (@report.template || {}).deep_stringify_keys
    aggregates = tmpl["aggregates"] || {}
    agg ? aggregates[key] = agg : aggregates.delete(key)

    @report.update!(template: tmpl.merge("aggregates" => aggregates))
    return finish_change("Total saved") if builder_request? || wizard_request?

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
    return finish_change("Sort saved") if builder_request? || wizard_request?

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
    Report.transaction do
      @report.grid_view_preferences.where("`key` LIKE ?", "#{relation}.%").destroy_all if activating_pivot
      @report.update!(template: tmpl.merge("joins" => joins))

      # The pivot block's place in the column order (H11); cleared pivots leave none (E9)
      if activating_pivot
        add_position_row("pivot:#{relation}", "#{relation.humanize} (pivot)")
      else
        @report.grid_view_preferences.where(key: "pivot:#{relation}").delete_all
      end
    end
    finish_change(activating_pivot ? "Pivot applied" : "Pivot cleared")
  end

  # PATCH /report_builder/:id/join_settings — turns "Only rows that have …" on
  # or off for one join. Edits just that join (update_template's deep merge
  # would replace the whole joins array). Only first-level has_many joins can
  # use it: one-per-row related data has at most one row anyway.
  # Worked examples H13, X8, X9.
  def update_join_settings
    authorize @report, :update?

    relation = params[:relation].to_s.strip
    config   = ReportBuilderConfig.new(@report.template)

    # X9 — unknown relation, or one-per-row / multi-step related data
    many_per_row = config.join_for(relation) && config.column_type.strategy_for(relation) == :grouped
    return render json: { errors: ["'#{relation}' isn't many-per-row related data on this report"] }, status: :unprocessable_entity unless many_per_row

    tmpl  = (@report.template || {}).deep_stringify_keys
    on    = params[:only_with_rows].to_s == "true"
    joins = (tmpl["joins"] || []).map do |j|
      next j unless j["relation"] == relation

      on ? j.merge("only_with_rows" => true) : j.except("only_with_rows")
    end
    @report.update!(template: tmpl.merge("joins" => joins))
    return finish_change("Related data setting saved") if builder_request? || wizard_request?

    render json: { ok: true }
  end

  # POST /report_builder/:id/formulas
  def add_formula
    authorize @report, :update?

    expression = params[:expression].to_s
    allowed_keys = @report.grid_view_preferences.pluck(:key).to_set { |k| k.split(";").first.strip }
    referenced   = expression.scan(/\[([^\]]+)\]/).flatten.map { |r| r.split(";").first.strip }
    bad          = referenced.reject { |r| allowed_keys.include?(r) }

    if bad.any?
      message = "Formula references unknown column(s): #{bad.join(', ')}"
      return finish_change(message, level: :danger,
                                    fallback: -> { redirect_to edit_report_builder_path(@report), alert: message })
    end

    tmpl = (@report.template || {}).deep_stringify_keys
    formulas = tmpl["formulas"] || []

    # Unique even when two formulas are added in the same second
    key   = "formula_#{Time.now.to_i}_#{SecureRandom.hex(2)}"
    label = params[:label].presence || "New Formula"
    formulas << { "key" => key, "label" => label, "expression" => expression }

    Report.transaction do
      @report.update!(template: tmpl.merge("formulas" => formulas))
      # The formula's place in the column order: last, draggable (H10)
      add_position_row("formula:#{key}", label)
    end
    finish_change("Added formula #{label}")
  end

  # DELETE /report_builder/:id/formulas/:key
  def remove_formula
    authorize @report, :update?

    tmpl = (@report.template || {}).deep_stringify_keys
    formulas = (tmpl["formulas"] || []).reject { |f| f["key"] == params[:key] }

    Report.transaction do
      @report.update!(template: tmpl.merge("formulas" => formulas))
      # No empty column left behind (E8)
      @report.grid_view_preferences.where(key: "formula:#{params[:key]}").delete_all
    end
    finish_change("Formula removed")
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

    # M16 — the sample rows come from the viewer's own scope
    engine = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity, user: current_user)
    rows   = engine.run(limit: 5)
    sample_row = rows.first || {}
    sample_row = referenced.index_with(0) if sample_row.empty?

    result = ReportBuilderFormulaService.validate(expression, sample_row)
    return render json: { ok: false, error: result } unless result == true

    render json: { ok: true, samples: formula_samples(expression, rows, engine.columns) }
  end

  private

  def drop_undo
    ReportBuilderUndo.drop!(@report) if @report&.persisted?
  end

  def set_report
    @report = Report.find(params[:id])
  end

  # The report page's address after Narrow down's Apply: the visit's `q` plus
  # "<field>_<operator>" = value, keeping its sort and page size. An operator
  # the field doesn't offer is dropped (delivery H10).
  def narrowed_params
    field  = params[:nf].to_s
    info   = ReportBuilderFilterField.new(config: ReportBuilderConfig.new(@report.template), key: field, entity: current_user.entity)
    op     = params[:nop].to_s
    q      = (params[:q]&.to_unsafe_h || {}).dup
    if info.operators.any? { |_, o| o == op }
      value = ReportBuilderFilterField::NO_VALUE_OPS.include?(op) ? "true" : params[:nv]
      q["#{field}_#{op}"] = value.is_a?(Array) ? value.compact_blank : value
    end
    { q: q.presence, sort: params[:sort].presence, dir: params[:dir].presence, per_page: params[:per_page].presence }.compact
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

      # Related data is totalled in SQL: only stored columns (E13)
      ReportBuilderColumnCatalog.related_columns_for(klass).any? { |c| c[:key] == field }
    else
      # Root columns must be readable on the row (E12)
      ReportBuilderColumnCatalog.columns_for(config.root_class).any? { |c| c[:key] == clean }
    end
  rescue StandardError
    false
  end

  # The formula's result on the first rows, each labelled with the row's first
  # column, formatted as the preview would show it (blank when it can't be
  # worked out, e.g. dividing by zero). Worked example H10.
  def formula_samples(expression, rows, columns)
    config    = ReportBuilderConfig.new(@report.template)
    formatter = ReportBuilderValueFormatter.new(config: config, entity: current_user.entity)
    first     = columns.first
    sample    = ReportBuilderDynamicColumn.new(key: "_sample", label: "Result")
    service   = ReportBuilderFormulaService.new([{ "key" => "_sample", "expression" => expression }])

    rows.map do |row|
      value = service.evaluate(row.dup)["_sample"]
      { row: first ? formatter.display(row[first.key], first) : "", value: formatter.display(value, sample) }
    end
  end

  # Adding a related column whose related data isn't on the report yet adds
  # that related data first — only for the curated, pack-allowed first-level
  # associations offered in the pickers (wizard step 2). Worked example H20.
  def auto_join_for(clean_key)
    parts = clean_key.split(".")
    return unless parts.size == 2

    relation = parts.first
    config = ReportBuilderConfig.new(@report.template)
    return if config.join_for(relation) || !config.valid?

    assoc = ReportBuilderModelDiscovery.associations_for(config.root_class, entity: current_user.entity)
                                       .find { |a| a[:name] == relation }
    return unless assoc

    tmpl = (@report.template || {}).deep_stringify_keys
    joins = (tmpl["joins"] || []) + [{ "relation" => relation, "model" => assoc[:model], "fk" => assoc[:foreign_key] }]
    @report.update!(template: tmpl.merge("joins" => joins))
  end

  # A position row for a formula ("formula:<key>") or pivot block
  # ("pivot:<relation>") at the end of the column order, so it can be dragged
  # like any column. The engine expands it into the real column(s). H10, H11.
  def add_position_row(key, label)
    return if @report.grid_view_preferences.exists?(key: key)

    max_seq = @report.grid_view_preferences.maximum(:sequence) || 0
    @report.grid_view_preferences.create!(key: key, name: label, label: label,
                                          entity_id: @report.entity_id, sequence: max_seq + 1)
  end

  # A newly added related column gets the total for its type saved straight
  # away (Sum for amounts, Latest date for dates, …), so it is never blank and
  # the wizard shows what is really stored. Worked examples H7, E2, H25.
  def store_default_aggregate(key)
    clean = key.to_s.split(";").first.strip
    return unless clean.include?(".")

    config = ReportBuilderConfig.new(@report.template)
    return if config.aggregate_for(clean)

    default = config.column_type.default_aggregate(clean)
    return unless default

    tmpl = (@report.template || {}).deep_stringify_keys
    @report.update!(template: tmpl.merge("aggregates" => (tmpl["aggregates"] || {}).merge(clean => default)))
  end

  # Everything the builder's settings panel needs: the config, the table, the
  # related data that can be added and the column lists
  def load_builder_state
    @config     = ReportBuilderConfig.new(@report.template)
    @root_class = begin
      @config.root_class
    rescue StandardError
      nil
    end
    return unless @root_class

    @associations = ReportBuilderModelDiscovery.associations_for(@root_class, entity: current_user.entity)
    load_builder_columns
  end

  # The preview's rows, columns, formatter and totals — the same rules as the
  # report page; a sample of a larger report says "Total (these N rows)" (trust
  # H24, E20). An engine error becomes @preview_error, shown in the frame (E19).
  def load_preview_state(limit: PREVIEW_LIMIT)
    @config    = ReportBuilderConfig.new(@report.template)
    @formatter = ReportBuilderValueFormatter.new(config: @config, entity: current_user.entity)
    @preview_error = nil

    # M16 — the preview shows only the rows the viewer may see
    engine   = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity, user: current_user,
                                            external_filters: params[:q])
    @rows    = engine.run(limit: limit)
    @columns = engine.columns
    @total   = engine.count
    @totals  = ReportBuilderTotals.new(rows: @rows, columns: @columns, config: @config,
                                       scope: @total > @rows.size ? :sample : :all)
  rescue StandardError => e
    Rails.logger.warn "[ReportBuilder] preview failed report=#{@report.id}: #{e.message}"
    @preview_error = e.message
    @rows = []
    @columns = []
    @total = 0
    @totals = nil
  end

  # Column lists for the builder and wizard pickers: what can be shown
  # (@root_columns / @joined_columns) and what can be filtered on
  # (@root_filter_columns / @joined_filter_columns). Worked examples E12, E13.
  def load_builder_columns
    @root_columns        = ReportBuilderColumnCatalog.columns_for(@root_class)
    @root_filter_columns = ReportBuilderColumnCatalog.filter_columns_for(@root_class)

    # Ensure all models are loaded so constantize works for joined models
    ReportBuilderModelDiscovery.all_models

    @joined_columns = {}
    @joined_filter_columns = {}
    @config.joins.each do |j| # rubocop:disable Rails/FindEach -- config.joins is a plain Array, not an AR::Relation
      klass = resolve_join_klass(@root_class, j[:relation])
      unless klass
        Rails.logger.warn "[ReportBuilder] Could not resolve relation #{j[:relation]} report=#{@report.id}"
        next
      end

      @joined_columns[j[:relation].to_s] = ReportBuilderColumnCatalog.related_columns_for(klass)
      @joined_filter_columns[j[:relation].to_s] = ReportBuilderColumnCatalog.filter_columns_for(klass)
    end
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

  # Readable columns of a model (the catalog decides; kept for the JSON
  # /report_builder/models endpoint)
  def columns_for_model(klass)
    ReportBuilderColumnCatalog.columns_for(klass)
  end
end
