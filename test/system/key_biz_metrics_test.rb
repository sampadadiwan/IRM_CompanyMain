require "application_system_test_case"

class KeyBizMetricsTest < ApplicationSystemTestCase
  setup do
    @key_biz_metric = key_biz_metrics(:one)
  end

  test "visiting the index" do
    visit key_biz_metrics_url
    assert_selector "h1", text: "Key biz metrics"
  end

  test "should create key biz metric" do
    visit key_biz_metrics_url
    click_on "New key biz metric"

    fill_in "Display value", with: @key_biz_metric.display_value
    fill_in "Metric type", with: @key_biz_metric.metric_type
    fill_in "Name", with: @key_biz_metric.name
    fill_in "Notes", with: @key_biz_metric.notes
    fill_in "Query", with: @key_biz_metric.query
    fill_in "Value", with: @key_biz_metric.value
    click_on "Create Key biz metric"

    assert_text "Key biz metric was successfully created"
    click_on "Back"
  end

  test "should update Key biz metric" do
    visit key_biz_metric_url(@key_biz_metric)
    click_on "Edit this key biz metric", match: :first

    fill_in "Display value", with: @key_biz_metric.display_value
    fill_in "Metric type", with: @key_biz_metric.metric_type
    fill_in "Name", with: @key_biz_metric.name
    fill_in "Notes", with: @key_biz_metric.notes
    fill_in "Query", with: @key_biz_metric.query
    fill_in "Value", with: @key_biz_metric.value
    click_on "Update Key biz metric"

    assert_text "Key biz metric was successfully updated"
    click_on "Back"
  end

  test "should destroy Key biz metric" do
    visit key_biz_metric_url(@key_biz_metric)
    click_on "Destroy this key biz metric", match: :first

    assert_text "Key biz metric was successfully destroyed"
  end
end
