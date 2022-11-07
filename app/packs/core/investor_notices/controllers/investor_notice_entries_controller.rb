class InvestorNoticeEntriesController < ApplicationController
  before_action :set_investor_notice_entry, only: %i[show edit update destroy]

  # GET /investor_notice_entries or /investor_notice_entries.json
  def index
    @investor_notice_entries = policy_scope(InvestorNoticeEntry)
  end

  # GET /investor_notice_entries/1 or /investor_notice_entries/1.json
  def show; end

  # GET /investor_notice_entries/new
  def new
    @investor_notice_entry = InvestorNoticeEntry.new(investor_notice_entry_params)
    authorize(@investor_notice_entry)
  end

  # GET /investor_notice_entries/1/edit
  def edit; end

  # POST /investor_notice_entries or /investor_notice_entries.json
  def create
    @investor_notice_entry = InvestorNoticeEntry.new(investor_notice_entry_params)
    authorize(@investor_notice_entry)

    respond_to do |format|
      if @investor_notice_entry.save
        format.html { redirect_to investor_notice_entry_url(@investor_notice_entry), notice: "Investor notice entry was successfully created." }
        format.json { render :show, status: :created, location: @investor_notice_entry }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_notice_entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_notice_entries/1 or /investor_notice_entries/1.json
  def update
    respond_to do |format|
      if @investor_notice_entry.update(investor_notice_entry_params)
        format.html { redirect_to investor_notice_entry_url(@investor_notice_entry), notice: "Investor notice entry was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_notice_entry }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_notice_entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_notice_entries/1 or /investor_notice_entries/1.json
  def destroy
    @investor_notice_entry.destroy

    respond_to do |format|
      format.html { redirect_to investor_notice_entries_url, notice: "Investor notice entry was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_notice_entry
    @investor_notice_entry = InvestorNoticeEntry.find(params[:id])
    authorize(@investor_notice_entry)
  end

  # Only allow a list of trusted parameters through.
  def investor_notice_entry_params
    params.require(:investor_notice_entry).permit(:investor_notice_id, :entity_id, :investor_id, :investor_entity_id, :active)
  end
end
