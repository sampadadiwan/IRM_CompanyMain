class VideoKycsController < ApplicationController
  before_action :set_video_kyc, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index search]

  # GET /video_kycs or /video_kycs.json
  def index
    @investor = nil
    @video_kycs = policy_scope(VideoKyc)
    if params[:investor_id]
      @investor = Investor.find(params[:investor_id])
      @video_kycs = @video_kycs.where(investor_id: params[:investor_id])
    end

    @video_kycs = @video_kycs.where(verified: params[:verified] == "true") if params[:verified].present?

    @pagy, @video_kycs = pagy(@video_kycs.includes(:investor, :entity))
  end

  def search
    query = params[:query]
    if query.present?

      entity_ids = [current_user.entity_id]

      @video_kycs = VideoKycIndex.filter(term: { entity_id: entity_ids })
                                 .query(query_string: { fields: VideoKycIndex::SEARCH_FIELDS,
                                                        query:, default_operator: 'and' })
      @pagy, @video_kycs = pagy(@video_kycs.page(params[:page]).objects)

      render "index"
    else
      redirect_to video_kycs_path(request.parameters)
    end
  end

  # GET /video_kycs/1 or /video_kycs/1.json
  def show; end

  # GET /video_kycs/new
  def new
    @video_kyc = VideoKyc.new(video_kyc_params)
    authorize(@video_kyc)
  end

  # GET /video_kycs/1/edit
  def edit; end

  # POST /video_kycs or /video_kycs.json
  def create
    @video_kyc = VideoKyc.new(video_kyc_params)
    authorize(@video_kyc)
    respond_to do |format|
      if @video_kyc.save
        format.html { redirect_to video_kyc_url(@video_kyc), notice: "Video kyc was successfully created." }
        format.json { render :show, status: :created, location: @video_kyc }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @video_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /video_kycs/1 or /video_kycs/1.json
  def update
    respond_to do |format|
      if @video_kyc.update(video_kyc_params)
        format.html { redirect_to video_kyc_url(@video_kyc), notice: "Video kyc was successfully updated." }
        format.json { render :show, status: :ok, location: @video_kyc }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @video_kyc.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /video_kycs/1 or /video_kycs/1.json
  def destroy
    @video_kyc.destroy

    respond_to do |format|
      format.html { redirect_to video_kycs_url, notice: "Video kyc was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_video_kyc
    @video_kyc = VideoKyc.find(params[:id])
    authorize(@video_kyc)
  end

  # Only allow a list of trusted parameters through.
  def video_kyc_params
    params.require(:video_kyc).permit(:investor_kyc_id, :entity_id, :user_id, :file)
  end
end
