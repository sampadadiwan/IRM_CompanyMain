class InvestorNoticeItemsController < ApplicationController
  before_action :set_investor_notice_item, only: %i[show edit update destroy]

  # GET /investor_notice_items or /investor_notice_items.json
  def index
    @investor_notice_items = InvestorNoticeItem.all
  end

  # GET /investor_notice_items/1 or /investor_notice_items/1.json
  def show; end

  # GET /investor_notice_items/new
  def new
    @investor_notice_item = InvestorNoticeItem.new
  end

  # GET /investor_notice_items/1/edit
  def edit; end

  # POST /investor_notice_items or /investor_notice_items.json
  def create
    @investor_notice_item = InvestorNoticeItem.new(investor_notice_item_params)

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
  end

  # Only allow a list of trusted parameters through.
  def investor_notice_item_params
    params.require(:investor_notice_item).permit(:investor_notice_id, :title, :details, :link)
  end
end
