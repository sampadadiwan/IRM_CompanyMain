require "test_helper"

class KeyBizMetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @key_biz_metric = key_biz_metrics(:one)
  end

  test "should get index" do
    get key_biz_metrics_url
    assert_response :success
  end

  test "should get new" do
    get new_key_biz_metric_url
    assert_response :success
  end

  test "should create key_biz_metric" do
    assert_difference("KeyBizMetric.count") do
      post key_biz_metrics_url, params: { key_biz_metric: { display_value: @key_biz_metric.display_value, metric_type: @key_biz_metric.metric_type, name: @key_biz_metric.name, notes: @key_biz_metric.notes, query: @key_biz_metric.query, value: @key_biz_metric.value } }
    end

    assert_redirected_to key_biz_metric_url(KeyBizMetric.last)
  end

  test "should show key_biz_metric" do
    get key_biz_metric_url(@key_biz_metric)
    assert_response :success
  end

  test "should get edit" do
    get edit_key_biz_metric_url(@key_biz_metric)
    assert_response :success
  end

  test "should update key_biz_metric" do
    patch key_biz_metric_url(@key_biz_metric), params: { key_biz_metric: { display_value: @key_biz_metric.display_value, metric_type: @key_biz_metric.metric_type, name: @key_biz_metric.name, notes: @key_biz_metric.notes, query: @key_biz_metric.query, value: @key_biz_metric.value } }
    assert_redirected_to key_biz_metric_url(@key_biz_metric)
  end

  test "should destroy key_biz_metric" do
    assert_difference("KeyBizMetric.count", -1) do
      delete key_biz_metric_url(@key_biz_metric)
    end

    assert_redirected_to key_biz_metrics_url
  end
end
