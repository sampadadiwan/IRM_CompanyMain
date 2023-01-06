require "application_system_test_case"

class CapitalRemittancePaymentsTest < ApplicationSystemTestCase
  setup do
    @capital_remittance_payment = capital_remittance_payments(:one)
  end

  test "visiting the index" do
    visit capital_remittance_payments_url
    assert_selector "h1", text: "Capital remittance payments"
  end

  test "should create capital remittance payment" do
    visit capital_remittance_payments_url
    click_on "New capital remittance payment"

    fill_in "Amount", with: @capital_remittance_payment.amount
    fill_in "Capital remittance", with: @capital_remittance_payment.capital_remittance_id
    fill_in "Entity", with: @capital_remittance_payment.entity_id
    fill_in "Fund", with: @capital_remittance_payment.fund_id
    fill_in "Payment date", with: @capital_remittance_payment.payment_date
    click_on "Create Capital remittance payment"

    assert_text "Capital remittance payment was successfully created"
    click_on "Back"
  end

  test "should update Capital remittance payment" do
    visit capital_remittance_payment_url(@capital_remittance_payment)
    click_on "Edit this capital remittance payment", match: :first

    fill_in "Amount", with: @capital_remittance_payment.amount
    fill_in "Capital remittance", with: @capital_remittance_payment.capital_remittance_id
    fill_in "Entity", with: @capital_remittance_payment.entity_id
    fill_in "Fund", with: @capital_remittance_payment.fund_id
    fill_in "Payment date", with: @capital_remittance_payment.payment_date
    click_on "Update Capital remittance payment"

    assert_text "Capital remittance payment was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital remittance payment" do
    visit capital_remittance_payment_url(@capital_remittance_payment)
    click_on "Destroy this capital remittance payment", match: :first

    assert_text "Capital remittance payment was successfully destroyed"
  end
end
