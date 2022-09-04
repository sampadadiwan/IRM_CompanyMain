require "application_system_test_case"

class CapitalDistributionPaymentsTest < ApplicationSystemTestCase
  setup do
    @capital_distribution_payment = capital_distribution_payments(:one)
  end

  test "visiting the index" do
    visit capital_distribution_payments_url
    assert_selector "h1", text: "Capital distribution payments"
  end

  test "should create capital distribution payment" do
    visit capital_distribution_payments_url
    click_on "New capital distribution payment"

    fill_in "Amount", with: @capital_distribution_payment.amount
    fill_in "Capital distribution", with: @capital_distribution_payment.capital_distribution_id
    fill_in "Entity", with: @capital_distribution_payment.entity_id
    fill_in "Form type", with: @capital_distribution_payment.form_type_id
    fill_in "Fund", with: @capital_distribution_payment.fund_id
    fill_in "Investor", with: @capital_distribution_payment.investor_id
    fill_in "Payment date", with: @capital_distribution_payment.payment_date
    fill_in "Properties", with: @capital_distribution_payment.properties
    click_on "Create Capital distribution payment"

    assert_text "Capital distribution payment was successfully created"
    click_on "Back"
  end

  test "should update Capital distribution payment" do
    visit capital_distribution_payment_url(@capital_distribution_payment)
    click_on "Edit this capital distribution payment", match: :first

    fill_in "Amount", with: @capital_distribution_payment.amount
    fill_in "Capital distribution", with: @capital_distribution_payment.capital_distribution_id
    fill_in "Entity", with: @capital_distribution_payment.entity_id
    fill_in "Form type", with: @capital_distribution_payment.form_type_id
    fill_in "Fund", with: @capital_distribution_payment.fund_id
    fill_in "Investor", with: @capital_distribution_payment.investor_id
    fill_in "Payment date", with: @capital_distribution_payment.payment_date
    fill_in "Properties", with: @capital_distribution_payment.properties
    click_on "Update Capital distribution payment"

    assert_text "Capital distribution payment was successfully updated"
    click_on "Back"
  end

  test "should destroy Capital distribution payment" do
    visit capital_distribution_payment_url(@capital_distribution_payment)
    click_on "Destroy this capital distribution payment", match: :first

    assert_text "Capital distribution payment was successfully destroyed"
  end
end
