class StampPapersController < ApplicationController
  before_action :set_stamp_paper, only: %i[show edit update destroy]

  # GET /stamp_papers or /stamp_papers.json
  def index
    @stamp_papers = policy_scope(StampPaper)
  end

  # GET /stamp_papers/1 or /stamp_papers/1.json
  def show; end

  # GET /stamp_papers/new
  def new
    @stamp_paper = StampPaper.new(stamp_paper_params)
    authorize @stamp_paper
  end

  # GET /stamp_papers/1/edit
  def edit; end

  # POST /stamp_papers or /stamp_papers.json
  def create
    @stamp_paper = StampPaper.new(stamp_paper_params)
    authorize @stamp_paper
    respond_to do |format|
      if @stamp_paper.save
        format.html { redirect_to stamp_paper_url(@stamp_paper), notice: "Stamp Paper was successfully created." }
        format.json { render :show, status: :created, location: @stamp_paper }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @stamp_paper.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /stamp_papers/1 or /stamp_papers/1.json
  def update
    respond_to do |format|
      if @stamp_paper.update(stamp_paper_params)
        format.html { redirect_to stamp_paper_url(@stamp_paper), notice: "Stamp Paper was successfully updated." }
        format.json { render :show, status: :ok, location: @stamp_paper }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @stamp_paper.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /stamp_papers/1 or /stamp_papers/1.json
  def destroy
    @stamp_paper.destroy

    respond_to do |format|
      format.html { redirect_to stamp_papers_url, notice: "Stamp Paper was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_stamp_paper
    @stamp_paper = StampPaper.find(params[:id])
    authorize @stamp_paper
  end

  # Only allow a list of trusted parameters through.
  def stamp_paper_params
    params.require(:stamp_paper).permit(:entity_id, :tags, :sign_on_page, :owner_id, :owner_type, :notes, :note_on_page)
  end
end
