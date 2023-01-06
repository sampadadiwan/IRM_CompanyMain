require "test_helper"

class CapitalRemittancePaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @capital_remittance_payment = capital_remittance_payments(:one)
  end

  test "should get index" do
    get capital_remittance_payments_url
    assert_response :success
  end

  test "should get new" do
    get new_capital_remittance_payment_url
    assert_response :success
  end

  test "should create capital_remittance_payment" do
    assert_difference("CapitalRemittancePayment.count") do
      post capital_remittance_payments_url, params: { capital_remittance_payment: { amount: @capital_remittance_payment.amount, capital_remittance_id: @capital_remittance_payment.capital_remittance_id, entity_id: @capital_remittance_payment.entity_id, fund_id: @capital_remittance_payment.fund_id, payment_date: @capital_remittance_payment.payment_date } }
    end

    assert_redirected_to capital_remittance_payment_url(CapitalRemittancePayment.last)
  end

  test "should show capital_remittance_payment" do
    get capital_remittance_payment_url(@capital_remittance_payment)
    assert_response :success
  end

  test "should get edit" do
    get edit_capital_remittance_payment_url(@capital_remittance_payment)
    assert_response :success
  end

  test "should update capital_remittance_payment" do
    patch capital_remittance_payment_url(@capital_remittance_payment), params: { capital_remittance_payment: { amount: @capital_remittance_payment.amount, capital_remittance_id: @capital_remittance_payment.capital_remittance_id, entity_id: @capital_remittance_payment.entity_id, fund_id: @capital_remittance_payment.fund_id, payment_date: @capital_remittance_payment.payment_date } }
    assert_redirected_to capital_remittance_payment_url(@capital_remittance_payment)
  end

  test "should destroy capital_remittance_payment" do
    assert_difference("CapitalRemittancePayment.count", -1) do
      delete capital_remittance_payment_url(@capital_remittance_payment)
    end

    assert_redirected_to capital_remittance_payments_url
  end
end
