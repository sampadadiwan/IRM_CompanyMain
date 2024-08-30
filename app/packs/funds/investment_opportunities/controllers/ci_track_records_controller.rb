class CiTrackRecordsController < ApplicationController
  before_action :set_ci_track_record, only: %i[show edit update destroy]

  # GET /ci_track_records or /ci_track_records.json
  def index
    @ci_track_records = CiTrackRecord.all
  end

  # GET /ci_track_records/1 or /ci_track_records/1.json
  def show; end

  # GET /ci_track_records/new
  def new
    @ci_track_record = CiTrackRecord.new(ci_track_record_params)
    @ci_track_record.entity = current_user.entity
    authorize @ci_track_record
  end

  # GET /ci_track_records/1/edit
  def edit; end

  # POST /ci_track_records or /ci_track_records.json
  def create
    @ci_track_record = CiTrackRecord.new(ci_track_record_params)
    @ci_track_record.entity = current_user.entity
    authorize @ci_track_record

    respond_to do |format|
      if @ci_track_record.save
        format.html { redirect_to ci_track_record_url(@ci_track_record), notice: "Ci track record was successfully created." }
        format.json { render :show, status: :created, location: @ci_track_record }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @ci_track_record.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /ci_track_records/1 or /ci_track_records/1.json
  def update
    respond_to do |format|
      if @ci_track_record.update(ci_track_record_params)
        format.html { redirect_to ci_track_record_url(@ci_track_record), notice: "Ci track record was successfully updated." }
        format.json { render :show, status: :ok, location: @ci_track_record }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @ci_track_record.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /ci_track_records/1 or /ci_track_records/1.json
  def destroy
    @ci_track_record.destroy!

    respond_to do |format|
      format.html { redirect_to ci_track_records_url, notice: "Ci track record was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ci_track_record
    @ci_track_record = CiTrackRecord.find(params[:id])
    authorize @ci_track_record
    @bread_crumbs = { "#{@ci_track_record.owner}": polymorphic_path(@ci_track_record.owner),
                      "#{@ci_track_record.name}": ci_track_record_path(@ci_track_record) }
  end

  # Only allow a list of trusted parameters through.
  def ci_track_record_params
    params.require(:ci_track_record).permit(:owner_id, :owner_type, :entity_id, :name, :value, :prefix, :suffix, :details)
  end
end
