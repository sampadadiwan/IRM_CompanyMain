class ReportBuilderController < ApplicationController
  before_action :set_report, only: %i[
    edit preview download update_template
    add_column remove_column
    add_join remove_join
    update_aggregate update_sort update_name
    update_pivot
  ]

  # GET /report_builder/models
  def models
    authorize Report, :index?
    roots = ReportBuilderModelDiscovery.roots
    render json: roots.map { |m|
      {
        name:    m.name,
        label:   m.name.humanize,
        pack:    ReportBuilderModelDiscovery.pack_for(m),
        columns: columns_for_model(m)
      }
    }
  end

  # GET /report_builder/associations?model=Investor
  def associations
    authorize Report, :index?
    klass = params[:model].constantize
    render json: ReportBuilderModelDiscovery.associations_for(klass)
  rescue NameError
    render json: { error: "Unknown model" }, status: :unprocessable_entity
  end

  # GET /report_builder/new
  def new
    authorize Report.new(entity: current_user.entity), :create?
    @root_models = ReportBuilderModelDiscovery.roots.group_by { |m| ReportBuilderModelDiscovery.pack_for(m) }
  end

  # POST /report_builder
  def create
    @report = Report.new(
      user:           current_user,
      entity:         current_user.entity,
      curr_role:      current_user.curr_role,
      name:           "Untitled Report",
      report_builder: true,
      url:            "/report_builder",
      template: {
        version:      1,
        root_model:   params[:root_model],
        joins:        [],
        aggregates:   {},
        root_filters: {},
        sort:         {}
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
    @config     = ReportBuilderConfig.new(@report.template)
    @root_class = @config.root_class rescue nil

    return unless @root_class

    @root_columns   = columns_for_model(@root_class)
    @associations   = ReportBuilderModelDiscovery.associations_for(@root_class)
    
    # Ensure all models are loaded so constantize works for joined models
    ReportBuilderModelDiscovery.all_models

    @joined_columns = @config.joins.each_with_object({}) do |j, h|
      model_name = j[:model].to_s
      klass = model_name.safe_constantize
      
      # Fallback: search all models if safe_constantize failed
      if klass.nil?
        klass = ReportBuilderModelDiscovery.all_models.find { |m| m.name == model_name }
      end

      if klass
        h[j[:relation].to_s] = columns_for_model(klass)
      else
        Rails.logger.warn "[ReportBuilder] Could not constantize model: #{model_name} for relation: #{j[:relation]}"
      end
    end
  end

  # GET /report_builder/:id/preview
  def preview
    authorize @report, :show?

    engine   = ReportBuilderQueryEngine.new(report: @report, entity: current_user.entity)
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

    redirect_back fallback_location: edit_report_builder_path(@report), 
                  notice: "Report generation started. You will be notified when it's ready."
  rescue StandardError => e
    redirect_back fallback_location: edit_report_builder_path(@report), 
                  alert: "Failed to start export: #{e.message}"
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

    key  = params[:key].to_s
    name = params[:name].presence || key.split(".").last.humanize
    unless @report.grid_view_preferences.exists?(key: key)
      # Get the next sequence number
      max_seq = @report.grid_view_preferences.maximum(:sequence) || 0
      @report.grid_view_preferences.create!(
        key:       key,
        name:      name,
        label:     params[:label].presence || name,
        entity_id: @report.entity_id,
        sequence:  max_seq + 1
      )
    end

    redirect_to edit_report_builder_path(@report)
  end

  # DELETE /report_builder/:id/columns/:gvp_id
  def remove_column
    authorize @report, :update?
    @report.grid_view_preferences.find(params[:gvp_id]).destroy
    redirect_to edit_report_builder_path(@report)
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

    redirect_to edit_report_builder_path(@report)
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

    redirect_to edit_report_builder_path(@report)
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
    render json: { ok: true }
  end

  # PATCH /report_builder/:id/sort
  def update_sort
    authorize @report, :update?

    tmpl = (@report.template || {}).deep_stringify_keys
    @report.update!(template: tmpl.merge("sort" => { "key" => params[:sort_key], "dir" => params[:sort_dir] }))
    render json: { ok: true }
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

    tmpl  = (@report.template || {}).deep_stringify_keys
    joins = (tmpl["joins"] || []).map do |j|
      if j["relation"] == relation
        if params[:clear].present?
          j.except("pivot")
        else
          j.merge("pivot" => {
            "group_by"  => params[:group_by].to_s.strip,
            "value_col" => params[:value_col].to_s.strip,
            "aggregate" => params[:aggregate].to_s.strip.presence || "sum"
          })
        end
      else
        j
      end
    end

    @report.update!(template: tmpl.merge("joins" => joins))
    redirect_to edit_report_builder_path(@report)
  end

  private

  def set_report
    @report = Report.find(params[:id])
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
        label:     c[:label].to_s.split(";").first.strip,
        key:       c[:key].to_s.split(";").first.strip,
        raw_key:   c[:key],
        raw_label: c[:label]
      }
    end.sort_by { |c| c[:label] }
  end
end
