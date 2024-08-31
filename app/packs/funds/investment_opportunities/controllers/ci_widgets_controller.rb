class CiWidgetsController < ApplicationController
  before_action :set_ci_widget, only: %i[show edit update destroy]

  # GET /ci_widgets or /ci_widgets.json
  def index
    @ci_widgets = policy_scope(CiWidget)
  end

  # GET /ci_widgets/1 or /ci_widgets/1.json
  def show; end

  # GET /ci_widgets/new
  def new
    @ci_widget = CiWidget.new(ci_widget_params)
    @ci_widget.entity = current_user.entity
    authorize @ci_widget
  end

  # GET /ci_widgets/1/edit
  def edit; end

  # POST /ci_widgets or /ci_widgets.json
  def create
    @ci_widget = CiWidget.new(ci_widget_params)
    @ci_widget.entity = current_user.entity
    authorize @ci_widget

    respond_to do |format|
      if @ci_widget.save
        format.html { redirect_to ci_widget_url(@ci_widget), notice: "Ci widget was successfully created." }
        format.json { render :show, status: :created, location: @ci_widget }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @ci_widget.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /ci_widgets/1 or /ci_widgets/1.json
  def update
    respond_to do |format|
      if @ci_widget.update(ci_widget_params)
        format.html { redirect_to ci_widget_url(@ci_widget), notice: "Ci widget was successfully updated." }
        format.json { render :show, status: :ok, location: @ci_widget }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @ci_widget.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /ci_widgets/1 or /ci_widgets/1.json
  def destroy
    @ci_widget.destroy!

    respond_to do |format|
      format.html { redirect_to ci_widgets_url, notice: "Ci widget was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ci_widget
    @ci_widget = CiWidget.find(params[:id])
    authorize @ci_widget
    @bread_crumbs = { "#{@ci_widget.owner}": polymorphic_path(@ci_widget.owner),
                      "#{@ci_widget.title}": ci_widget_path(@ci_widget) }
  end

  # Only allow a list of trusted parameters through.
  def ci_widget_params
    params.require(:ci_widget).permit(:owner_id, :owner_type, :entity_id, :title, :details_top, :details, :url, :image, :image_placement)
  end
end
