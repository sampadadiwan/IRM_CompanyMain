require "test_helper"

class CapitalDistributionPaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @capital_distribution_payment = capital_distribution_payments(:one)
  end

  test "should get index" do
    get capital_distribution_payments_url
    assert_response :success
  end

  test "should get new" do
    get new_capital_distribution_payment_url
    assert_response :success
  end

  test "should create capital_distribution_payment" do
    assert_difference("CapitalDistributionPayment.count") do
      post capital_distribution_payments_url, params: { capital_distribution_payment: { amount: @capital_distribution_payment.amount, capital_distribution_id: @capital_distribution_payment.capital_distribution_id, entity_id: @capital_distribution_payment.entity_id, form_type_id: @capital_distribution_payment.form_type_id, fund_id: @capital_distribution_payment.fund_id, investor_id: @capital_distribution_payment.investor_id, payment_date: @capital_distribution_payment.payment_date, properties: @capital_distribution_payment.properties } }
    end

    assert_redirected_to capital_distribution_payment_url(CapitalDistributionPayment.last)
  end

  test "should show capital_distribution_payment" do
    get capital_distribution_payment_url(@capital_distribution_payment)
    assert_response :success
  end

  test "should get edit" do
    get edit_capital_distribution_payment_url(@capital_distribution_payment)
    assert_response :success
  end

  test "should update capital_distribution_payment" do
    patch capital_distribution_payment_url(@capital_distribution_payment), params: { capital_distribution_payment: { amount: @capital_distribution_payment.amount, capital_distribution_id: @capital_distribution_payment.capital_distribution_id, entity_id: @capital_distribution_payment.entity_id, form_type_id: @capital_distribution_payment.form_type_id, fund_id: @capital_distribution_payment.fund_id, investor_id: @capital_distribution_payment.investor_id, payment_date: @capital_distribution_payment.payment_date, properties: @capital_distribution_payment.properties } }
    assert_redirected_to capital_distribution_payment_url(@capital_distribution_payment)
  end

  test "should destroy capital_distribution_payment" do
    assert_difference("CapitalDistributionPayment.count", -1) do
      delete capital_distribution_payment_url(@capital_distribution_payment)
    end

    assert_redirected_to capital_distribution_payments_url
  end
end
