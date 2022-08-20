require "test_helper"

class CapitalCallsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @capital_call = capital_calls(:one)
  end

  test "should get index" do
    get capital_calls_url
    assert_response :success
  end

  test "should get new" do
    get new_capital_call_url
    assert_response :success
  end

  test "should create capital_call" do
    assert_difference("CapitalCall.count") do
      post capital_calls_url, params: { capital_call: { due_date: @capital_call.due_date, entity_id: @capital_call.entity_id, fund_id: @capital_call.fund_id, name: @capital_call.name, notes: @capital_call.notes, percentage_called: @capital_call.percentage_called } }
    end

    assert_redirected_to capital_call_url(CapitalCall.last)
  end

  test "should show capital_call" do
    get capital_call_url(@capital_call)
    assert_response :success
  end

  test "should get edit" do
    get edit_capital_call_url(@capital_call)
    assert_response :success
  end

  test "should update capital_call" do
    patch capital_call_url(@capital_call), params: { capital_call: { due_date: @capital_call.due_date, entity_id: @capital_call.entity_id, fund_id: @capital_call.fund_id, name: @capital_call.name, notes: @capital_call.notes, percentage_called: @capital_call.percentage_called } }
    assert_redirected_to capital_call_url(@capital_call)
  end

  test "should destroy capital_call" do
    assert_difference("CapitalCall.count", -1) do
      delete capital_call_url(@capital_call)
    end

    assert_redirected_to capital_calls_url
  end
end
