class CiProfilesController < ApplicationController
  before_action :set_ci_profile, only: %i[show edit update destroy]
  layout :set_layout, only: [:show]

  # GET /ci_profiles or /ci_profiles.json
  def index
    @ci_profiles = policy_scope(CiProfile)
  end

  # GET /ci_profiles/1 or /ci_profiles/1.json
  def show; end

  def set_layout
    params[:layout] || "application"
  end

  # GET /ci_profiles/new
  def new
    @ci_profile = CiProfile.new
    @ci_profile.entity = current_user.entity
    authorize @ci_profile
  end

  # GET /ci_profiles/1/edit
  def edit; end

  # POST /ci_profiles or /ci_profiles.json
  def create
    @ci_profile = CiProfile.new(ci_profile_params)
    @ci_profile.entity = current_user.entity
    # @ci_profile.fund_size_cents = ci_profile_params[:fund_size].to_d * 100
    # @ci_profile.min_investment_cents = ci_profile_params[:min_investment].to_d * 100

    authorize @ci_profile
    respond_to do |format|
      if @ci_profile.save
        format.html { redirect_to ci_profile_url(@ci_profile), notice: "Ci profile was successfully created." }
        format.json { render :show, status: :created, location: @ci_profile }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @ci_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /ci_profiles/1 or /ci_profiles/1.json
  def update
    respond_to do |format|
      if @ci_profile.update(ci_profile_params)
        format.html { redirect_to ci_profile_url(@ci_profile), notice: "Ci profile was successfully updated." }
        format.json { render :show, status: :ok, location: @ci_profile }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @ci_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /ci_profiles/1 or /ci_profiles/1.json
  def destroy
    @ci_profile.destroy!

    respond_to do |format|
      format.html { redirect_to ci_profiles_url, notice: "Ci profile was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ci_profile
    @ci_profile = CiProfile.find(params[:id])
    authorize @ci_profile
  end

  # Only allow a list of trusted parameters through.
  def ci_profile_params
    params.require(:ci_profile).permit(:entity_id, :fund_id, :title, :geography, :stage, :sector, :fund_size, :min_investment, :status, :details, :currency, track_record: {})
  end
end
