class ViewedBiesController < ApplicationController
  before_action :set_viewed_by, only: %i[show edit update destroy]

  # GET /viewed_bies
  def index
    @q = ViewedBy.ransack(params[:q])
    @viewed_bies = policy_scope(@q.result)
  end

  # GET /viewed_bies/1
  def show; end

  # GET /viewed_bies/new
  def new
    @viewed_by = ViewedBy.new
    authorize @viewed_by
  end

  # GET /viewed_bies/1/edit
  def edit; end

  # POST /viewed_bies
  def create
    @viewed_by = ViewedBy.new(viewed_by_params)
    authorize @viewed_by
    if @viewed_by.save
      redirect_to @viewed_by, notice: "Viewed by was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /viewed_bies/1
  def update
    if @viewed_by.update(viewed_by_params)
      redirect_to @viewed_by, notice: "Viewed by was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /viewed_bies/1
  def destroy
    @viewed_by.destroy!
    redirect_to viewed_bies_url, notice: "Viewed by was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_viewed_by
    @viewed_by = ViewedBy.find(params[:id])
    authorize @viewed_by
  end

  # Only allow a list of trusted parameters through.
  def viewed_by_params
    params.require(:viewed_by).permit(:owner_id, :owner_type, :user_id)
  end
end
