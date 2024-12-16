class DashboardWidgetsController < ApplicationController
  before_action :set_dashboard_widget, only: %i[show edit update destroy]

  # GET /dashboard_widgets
  def index
    @q = DashboardWidget.ransack(params[:q])
    @dashboard_widgets = policy_scope(@q.result).includes(:owner).page(params[:page])
  end

  # GET /dashboard_widgets/1
  def show; end

  def ops_dashboard
    authorize DashboardWidget
  end

  # GET /dashboard_widgets/new
  def new
    @dashboard_widget = DashboardWidget.new
    @dashboard_widget.entity_id = current_user.entity_id
    authorize @dashboard_widget
  end

  # GET /dashboard_widgets/1/edit
  def edit; end

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

  # Use callbacks to share common setup or constraints between actions.
  def set_dashboard_widget
    @dashboard_widget = DashboardWidget.find(params[:id])
    authorize @dashboard_widget
  end

  # Only allow a list of trusted parameters through.
  def dashboard_widget_params
    params.require(:dashboard_widget).permit(:dashboard_name, :entity_id, :owner_id, :owner_type, :widget_name, :position, :metadata, :enabled, :tags, :size)
  end
end
