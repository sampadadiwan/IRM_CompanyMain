class InvestorNoticesController < ApplicationController
  before_action :set_investor_notice, only: %i[show edit update destroy]

  # GET /investor_notices or /investor_notices.json
  def index
    @investor_notices = policy_scope(InvestorNotice)
  end

  # GET /investor_notices/1 or /investor_notices/1.json
  def show; end

  # GET /investor_notices/new
  def new
    @investor_notice = params[:investor_notice].present? ? InvestorNotice.new(investor_notice_params) : InvestorNotice.new
    @investor_notice.entity_id = current_user.entity_id
    @investor_notice.start_date = Time.zone.today
    @investor_notice.end_date = Time.zone.today + 1.week
    @investor_notice.generate = true
    @investor_notice.active = true
    authorize(@investor_notice)
  end

  # GET /investor_notices/1/edit
  def edit; end

  # POST /investor_notices or /investor_notices.json
  def create
    @investor_notice = InvestorNotice.new(investor_notice_params)
    @investor_notice.entity_id = current_user.entity_id
    authorize(@investor_notice)

    respond_to do |format|
      if @investor_notice.save
        format.html { redirect_to investor_notice_url(@investor_notice), notice: "Investor notice was successfully created." }
        format.json { render :show, status: :created, location: @investor_notice }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_notice.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_notices/1 or /investor_notices/1.json
  def update
    respond_to do |format|
      if @investor_notice.update(investor_notice_params)
        format.html { redirect_to investor_notice_url(@investor_notice), notice: "Investor notice was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_notice }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_notice.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_notices/1 or /investor_notices/1.json
  def destroy
    @investor_notice.destroy

    respond_to do |format|
      format.html { redirect_to investor_notices_url, notice: "Investor notice was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_notice
    @investor_notice = InvestorNotice.find(params[:id])
    authorize(@investor_notice)
  end

  # Only allow a list of trusted parameters through.
  def investor_notice_params
    params.require(:investor_notice).permit(:entity_id, :owner_id, :owner_type, :start_date, :end_date, :active, :details, :title, :link, :access_rights_metadata, :btn_label, :generate, :category)
  end
end
