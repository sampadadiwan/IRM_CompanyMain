class TickerFeedsController < ApplicationController
  before_action :set_ticker_feed, only: %i[show edit update destroy]

  # GET /ticker_feeds
  def index
    @q = TickerFeed.ransack(params[:q])
    @ticker_feeds = policy_scope(@q.result)
    @pagy, @ticker_feeds = pagy(@ticker_feeds)
  end

  # GET /ticker_feeds/1
  def show; end

  # GET /ticker_feeds/new
  def new
    @ticker_feed = TickerFeed.new
    @ticker_feed.for_date = Time.zone.today
    @ticker_feed.for_time = Time.zone.now
    @ticker_feed.price_type = 'ID'
    @ticker_feed.currency = 'INR'
    @ticker_feed.source = 'Manual'
    authorize @ticker_feed
  end

  # GET /ticker_feeds/1/edit
  def edit; end

  # POST /ticker_feeds
  def create
    @ticker_feed = TickerFeed.new(ticker_feed_params)
    @ticker_feed.price_cents = params[:ticker_feed][:price].to_f * 100
    authorize @ticker_feed
    if @ticker_feed.save
      redirect_to @ticker_feed, notice: "Ticker feed was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /ticker_feeds/1
  def update
    @ticker_feed.price_cents = params[:ticker_feed][:price].to_f * 100
    if @ticker_feed.update(ticker_feed_params)
      redirect_to @ticker_feed, notice: "Ticker feed was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /ticker_feeds/1
  def destroy
    @ticker_feed.destroy!
    redirect_to ticker_feeds_url, notice: "Ticker feed was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_ticker_feed
    @ticker_feed = TickerFeed.find(params[:id])
    authorize @ticker_feed
  end

  # Only allow a list of trusted parameters through.
  def ticker_feed_params
    params.require(:ticker_feed).permit(:ticker, :currency, :name, :source, :for_date, :for_time, :price_type)
  end
end
