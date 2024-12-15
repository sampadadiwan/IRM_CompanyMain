require "application_system_test_case"

class TickerFeedsTest < ApplicationSystemTestCase
  setup do
    @ticker_feed = ticker_feeds(:one)
  end

  test "visiting the index" do
    visit ticker_feeds_url
    assert_selector "h1", text: "Ticker feeds"
  end

  test "should create ticker feed" do
    visit ticker_feeds_url
    click_on "New ticker feed"

    fill_in "For date", with: @ticker_feed.for_date
    fill_in "For time", with: @ticker_feed.for_time
    fill_in "Name", with: @ticker_feed.name
    fill_in "Price cents", with: @ticker_feed.price_cents
    fill_in "Price type", with: @ticker_feed.price_type
    fill_in "Source", with: @ticker_feed.source
    fill_in "Ticker", with: @ticker_feed.ticker
    click_on "Create Ticker feed"

    assert_text "Ticker feed was successfully created"
    click_on "Back"
  end

  test "should update Ticker feed" do
    visit ticker_feed_url(@ticker_feed)
    click_on "Edit this ticker feed", match: :first

    fill_in "For date", with: @ticker_feed.for_date
    fill_in "For time", with: @ticker_feed.for_time.to_s
    fill_in "Name", with: @ticker_feed.name
    fill_in "Price cents", with: @ticker_feed.price_cents
    fill_in "Price type", with: @ticker_feed.price_type
    fill_in "Source", with: @ticker_feed.source
    fill_in "Ticker", with: @ticker_feed.ticker
    click_on "Update Ticker feed"

    assert_text "Ticker feed was successfully updated"
    click_on "Back"
  end

  test "should destroy Ticker feed" do
    visit ticker_feed_url(@ticker_feed)
    click_on "Destroy this ticker feed", match: :first

    assert_text "Ticker feed was successfully destroyed"
  end
end
