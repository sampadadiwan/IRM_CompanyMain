require "test_helper"

class TickerFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ticker_feed = ticker_feeds(:one)
  end

  test "should get index" do
    get ticker_feeds_url
    assert_response :success
  end

  test "should get new" do
    get new_ticker_feed_url
    assert_response :success
  end

  test "should create ticker_feed" do
    assert_difference("TickerFeed.count") do
      post ticker_feeds_url, params: { ticker_feed: { for_date: @ticker_feed.for_date, for_time: @ticker_feed.for_time, name: @ticker_feed.name, price_cents: @ticker_feed.price_cents, price_type: @ticker_feed.price_type, source: @ticker_feed.source, ticker: @ticker_feed.ticker } }
    end

    assert_redirected_to ticker_feed_url(TickerFeed.last)
  end

  test "should show ticker_feed" do
    get ticker_feed_url(@ticker_feed)
    assert_response :success
  end

  test "should get edit" do
    get edit_ticker_feed_url(@ticker_feed)
    assert_response :success
  end

  test "should update ticker_feed" do
    patch ticker_feed_url(@ticker_feed), params: { ticker_feed: { for_date: @ticker_feed.for_date, for_time: @ticker_feed.for_time, name: @ticker_feed.name, price_cents: @ticker_feed.price_cents, price_type: @ticker_feed.price_type, source: @ticker_feed.source, ticker: @ticker_feed.ticker } }
    assert_redirected_to ticker_feed_url(@ticker_feed)
  end

  test "should destroy ticker_feed" do
    assert_difference("TickerFeed.count", -1) do
      delete ticker_feed_url(@ticker_feed)
    end

    assert_redirected_to ticker_feeds_url
  end
end
