class InvestorNoticeItemsController < ApplicationController
  before_action :set_investor_notice_item, only: %i[show edit update destroy]

  # GET /investor_notice_items or /investor_notice_items.json
  def index
    authorize(InvestorNoticeItem)
    @investor_notice_items = policy_scope(InvestorNoticeItem)
  end

  # GET /investor_notice_items/1 or /investor_notice_items/1.json
  def show; end

  # GET /investor_notice_items/new
  def new
    @investor_notice_item = InvestorNoticeItem.new(entity_id: current_user.entity_id)
    authorize(@investor_notice_item)
  end

  # GET /investor_notice_items/1/edit
  def edit; end

  # POST /investor_notice_items or /investor_notice_items.json
  def create
    @investor_notice_item = InvestorNoticeItem.new(investor_notice_item_params)
    # entity_id is normally set by the before_save `set_entity_id` callback,
    # but the policy check below runs before save — set it here from the
    # referenced parent notice so belongs_to_entity? has something to compare,
    # and so this doubles as verifying the notice actually belongs to the
    # current user's GP (a nil investor_notice yields a nil entity_id, which
    # belongs_to_entity? correctly denies).
    @investor_notice_item.entity_id = @investor_notice_item.investor_notice&.entity_id
    authorize(@investor_notice_item)

    respond_to do |format|
      if @investor_notice_item.save
        format.html { redirect_to investor_notice_item_url(@investor_notice_item), notice: "Investor notice item was successfully created." }
        format.json { render :show, status: :created, location: @investor_notice_item }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_notice_item.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_notice_items/1 or /investor_notice_items/1.json
  def update
    respond_to do |format|
      if @investor_notice_item.update(investor_notice_item_params)
        format.html { redirect_to investor_notice_item_url(@investor_notice_item), notice: "Investor notice item was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_notice_item }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_notice_item.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_notice_items/1 or /investor_notice_items/1.json
  def destroy
    @investor_notice_item.destroy

    respond_to do |format|
      format.html { redirect_to investor_notice_items_url, notice: "Investor notice item was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_notice_item
    @investor_notice_item = InvestorNoticeItem.find(params[:id])
    authorize(@investor_notice_item)
  end

  # Only allow a list of trusted parameters through.
  def investor_notice_item_params
    # link can carry [user.xxx] variables (see InvestorNoticeLinkInterpolator)
    # and criteria is a Dentaku expression (see InvestorNoticeCriteriaEvaluator)
    # — same support-only gate as InvestorNotice#criteria.
    if current_user.support?
      params.require(:investor_notice_item).permit(:investor_notice_id, :title, :details, :link, :criteria)
    else
      params.require(:investor_notice_item).permit(:investor_notice_id, :title, :details)
    end
  end
end
