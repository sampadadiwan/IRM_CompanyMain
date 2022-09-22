class HoldingAuditTrailsController < ApplicationController
  before_action :set_holding_audit_trail, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index search]

  # GET /holding_audit_trails or /holding_audit_trails.json
  def index
    @holding_audit_trails = policy_scope(HoldingAuditTrail)
    @holding_audit_trails = @holding_audit_trails.where(ref_id: params[:ref_id]) if params[:ref_id].present?
    @holding_audit_trails = @holding_audit_trails.where(ref_type: params[:ref_type]) if params[:ref_type].present?

    @holding_audit_trails = @holding_audit_trails.order("id desc").page params[:page]
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @holding_audit_trails = if current_user.has_role?(:super)

                                HoldingAuditTrailIndex.query(query_string: { fields: HoldingAuditTrailIndex::SEARCH_FIELDS,
                                                                             query:, default_operator: 'and' }).objects

                              else
                                HoldingAuditTrailIndex.filter(term: { entity_id: @entity.id })
                                                      .query(query_string: { fields: HoldingAuditTrailIndex::SEARCH_FIELDS,
                                                                             query:, default_operator: 'and' }).objects
                              end

    end
    render "index"
  end

  # GET /holding_audit_trails/1 or /holding_audit_trails/1.json
  def show; end

  # GET /holding_audit_trails/new
  def new
    @holding_audit_trail = HoldingAuditTrail.new
    authorize(@holding_audit_trail)
  end

  # GET /holding_audit_trails/1/edit
  def edit; end

  # POST /holding_audit_trails or /holding_audit_trails.json
  def create
    @holding_audit_trail = HoldingAuditTrail.new(holding_audit_trail_params)
    authorize(@holding_audit_trail)
    respond_to do |format|
      if @holding_audit_trail.save
        format.html { redirect_to holding_audit_trail_url(@holding_audit_trail), notice: "Holding audit trail was successfully created." }
        format.json { render :show, status: :created, location: @holding_audit_trail }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @holding_audit_trail.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /holding_audit_trails/1 or /holding_audit_trails/1.json
  def update
    respond_to do |format|
      if @holding_audit_trail.update(holding_audit_trail_params)
        format.html { redirect_to holding_audit_trail_url(@holding_audit_trail), notice: "Holding audit trail was successfully updated." }
        format.json { render :show, status: :ok, location: @holding_audit_trail }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @holding_audit_trail.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /holding_audit_trails/1 or /holding_audit_trails/1.json
  def destroy
    @holding_audit_trail.destroy

    respond_to do |format|
      format.html { redirect_to holding_audit_trails_url, notice: "Holding audit trail was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_holding_audit_trail
    @holding_audit_trail = HoldingAuditTrail.find(params[:id])
    authorize(@holding_audit_trail)
  end

  # Only allow a list of trusted parameters through.
  def holding_audit_trail_params
    params.require(:holding_audit_trail).permit(:action, :action_id, :owner, :quantity, :operation, :ref_id, :ref_type, :comments, :entity_id)
  end
end
