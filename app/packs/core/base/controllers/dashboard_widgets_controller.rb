class DashboardWidgetsController < ApplicationController
  helper CapitalCommitmentDashboardHelper
  before_action :set_dashboard_widget, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index search bulk_actions metadata_help]

  # GET /dashboard_widgets
  def index
    @bread_crumbs = { Widgets: dashboard_widgets_path }
    @q = DashboardWidget.ransack(params[:q])
    @dashboard_widgets = policy_scope(@q.result).includes(:owner)
    @dashboard_widgets = @dashboard_widgets.order(:position) if @dashboard_widgets.arel.orders.blank? && params.dig(:q, :s).blank?
    @dashboard_widgets = @dashboard_widgets.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @pagy, @dashboard_widgets = pagy(@dashboard_widgets) unless request.format == "xlsx"
  end

  def metadata_help
    dashboard_name = params[:dashboard_name]
    widget_name = params[:widget_name]
    @dashboard_widget = DashboardWidget::WIDGETS[dashboard_name].find { |w| w.widget_name == widget_name }
  end

  # GET /dashboard_widgets/1
  def show; end

  def dashboard
    @dashboard_name = params[:dashboard_name] || "Ops Dashboard"
    @dashboard_names, @name = resolve_dashboard(@dashboard_name, params[:name])
    authorize DashboardWidget
  end

  # GET /dashboard_widgets/new
  def new
    @bread_crumbs = { Widgets: dashboard_widgets_path, New: nil }
    @dashboard_widget = DashboardWidget.new(params.fetch(:dashboard_widget, {}).permit(:dashboard_name, :name))
    @dashboard_widget.entity_id = current_user.entity_id
    authorize @dashboard_widget
  end

  # POST /dashboard_widgets/setup_lp_layout — creates the plain "LP" layout with the starter widgets; does nothing
  # if it already exists (E52a). Worked examples H8, E52a — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  def setup_lp_layout
    authorize DashboardWidget.new(entity_id: current_user.entity_id), :manage_lp_layouts?
    DashboardWidget.transaction do
      copy_lp_widgets("LP", starter_lp_widgets) unless lp_layout_exists?("LP")
    end
    redirect_to dashboard_widgets_path(q: DashboardWidget.layout_filter("LP")), notice: "LP layout ready."
  end

  # POST /dashboard_widgets/new_lp_layout — "LP, <tag>" for companies with that tag, starting as a copy of "LP"
  # (E88). Refused if a layout for that tag exists. Worked example E88.
  def new_lp_layout
    authorize DashboardWidget.new(entity_id: current_user.entity_id), :manage_lp_layouts?
    tag = params[:tag].to_s.strip.first(90)
    name = "LP, #{tag}"
    return redirect_back_or_to(dashboard_widgets_path, alert: "Enter a tag for the new LP layout.") if tag.blank?
    return redirect_back_or_to(dashboard_widgets_path, alert: "An LP layout for this tag already exists.") if lp_layout_exists?(name)

    DashboardWidget.transaction do
      plain = DashboardWidget.where(entity_id: current_user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name: "LP").order(:position)
      copy_lp_widgets(name, plain.exists? ? plain.to_a : starter_lp_widgets)
    end
    redirect_to dashboard_widgets_path(q: DashboardWidget.layout_filter(name)), notice: "LP layout \"#{name}\" created."
  end

  # GET /dashboard_widgets/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
  end

  # POST /dashboard_widgets
  def create
    @dashboard_widget = DashboardWidget.new(dashboard_widget_params)
    @dashboard_widget.entity_id = current_user.entity_id
    authorize @dashboard_widget
    if @dashboard_widget.save
      redirect_to @dashboard_widget, notice: "Dashboard widget was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /dashboard_widgets/1
  def update
    if @dashboard_widget.update(dashboard_widget_params)
      redirect_to @dashboard_widget, notice: "Dashboard widget was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /dashboard_widgets/1
  def destroy
    @dashboard_widget.destroy!
    redirect_to dashboard_widgets_url, notice: "Dashboard widget was successfully destroyed.", status: :see_other
  end

  private

  # Is there already an LP layout with these tokens (ignoring case and spaces)?
  def lp_layout_exists?(name)
    tokens = DashboardWidget.layout_tokens(name).sort
    DashboardWidget.lp_layout_names_for(current_user.entity_id).any? { |existing| DashboardWidget.layout_tokens(existing).sort == tokens }
  end

  # Catalogue entries for the starter widgets (Data Card, Key KPIs, Valuations) — Key KPIs only with the KPI module (E97)
  def starter_lp_widgets
    catalogue = DashboardWidget::PORTFOLIO_COMPANY_WIDGETS.index_by(&:widget_name)
    (DashboardWidget::LP_STARTER_WIDGETS & DashboardWidget.lp_safe_widget_names(current_user.entity)).map { |name| catalogue.fetch(name) }
  end

  # Saves copies of the given widgets into an LP layout (widget, size, position, labels, metadata)
  def copy_lp_widgets(name, widgets)
    widgets.each_with_index do |widget, index|
      DashboardWidget.create!(entity_id: current_user.entity_id, dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, name:,
                              widget_name: widget.widget_name, size: widget.size, position: widget.position || (index + 1),
                              tags: widget.tags.presence || widget.widget_name, enabled: true,
                              metadata: widget.metadata.presence || DashboardWidget::LP_STARTER_METADATA[widget.widget_name],
                              display_name: true, tag_list: widget.tag_list)
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_dashboard_widget
    @dashboard_widget = DashboardWidget.find(params[:id])
    authorize @dashboard_widget
    @bread_crumbs = { Widgets: dashboard_widgets_path }
    @bread_crumbs[@dashboard_widget.dashboard_name.to_s] = dashboard_widgets_path(q: RansackQueryBuilder.single("dashboard_name", :eq, @dashboard_widget.dashboard_name)) if @dashboard_widget.dashboard_name.present?

    @bread_crumbs[@dashboard_widget.widget_name.to_s] = dashboard_widget_path(@dashboard_widget)
  end

  # Only allow a list of trusted parameters through.
  def dashboard_widget_params
    params.require(:dashboard_widget).permit(:dashboard_name, :name, :entity_id, :owner_id, :owner_type, :widget_name, :position, :metadata, :enabled, :tags, :size, :display_name, :display_tag, :show_menu, :tag_list)
  end
end
