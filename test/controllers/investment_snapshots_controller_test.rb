require "test_helper"

class InvestmentSnapshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investment_snapshot = investment_snapshots(:one)
  end

  test "should get index" do
    get investment_snapshots_url
    assert_response :success
  end

  test "should get new" do
    get new_investment_snapshot_url
    assert_response :success
  end

  test "should create investment_snapshot" do
    assert_difference("InvestmentSnapshot.count") do
      post investment_snapshots_url, params: { investment_snapshot: { amount_cents: @investment_snapshot.amount_cents, anti_dilution: @investment_snapshot.anti_dilution, as_of: @investment_snapshot.as_of, category: @investment_snapshot.category, currency: @investment_snapshot.currency, current_value: @investment_snapshot.current_value, deleted_at: @investment_snapshot.deleted_at, diluted_percentage: @investment_snapshot.diluted_percentage, diluted_quantity: @investment_snapshot.diluted_quantity, employee_holdings: @investment_snapshot.employee_holdings, entity_id: @investment_snapshot.entity_id, funding_round_id: @investment_snapshot.funding_round_id, initial_value: @investment_snapshot.initial_value, investment_date: @investment_snapshot.investment_date, investment_id: @investment_snapshot.investment_id, investment_instrument: @investment_snapshot.investment_instrument, investment_type: @investment_snapshot.investment_type, investor_id: @investment_snapshot.investor_id, investor_type: @investment_snapshot.investor_type, liq_pref_type: @investment_snapshot.liq_pref_type, liquidation_preference: @investment_snapshot.liquidation_preference, percentage_holding: @investment_snapshot.percentage_holding, price_cents: @investment_snapshot.price_cents, quantity: @investment_snapshot.quantity, spv: @investment_snapshot.spv, status: @investment_snapshot.status, tag: @investment_snapshot.tag, units: @investment_snapshot.units } }
    end

    assert_redirected_to investment_snapshot_url(InvestmentSnapshot.last)
  end

  test "should show investment_snapshot" do
    get investment_snapshot_url(@investment_snapshot)
    assert_response :success
  end

  test "should get edit" do
    get edit_investment_snapshot_url(@investment_snapshot)
    assert_response :success
  end

  test "should update investment_snapshot" do
    patch investment_snapshot_url(@investment_snapshot), params: { investment_snapshot: { amount_cents: @investment_snapshot.amount_cents, anti_dilution: @investment_snapshot.anti_dilution, as_of: @investment_snapshot.as_of, category: @investment_snapshot.category, currency: @investment_snapshot.currency, current_value: @investment_snapshot.current_value, deleted_at: @investment_snapshot.deleted_at, diluted_percentage: @investment_snapshot.diluted_percentage, diluted_quantity: @investment_snapshot.diluted_quantity, employee_holdings: @investment_snapshot.employee_holdings, entity_id: @investment_snapshot.entity_id, funding_round_id: @investment_snapshot.funding_round_id, initial_value: @investment_snapshot.initial_value, investment_date: @investment_snapshot.investment_date, investment_id: @investment_snapshot.investment_id, investment_instrument: @investment_snapshot.investment_instrument, investment_type: @investment_snapshot.investment_type, investor_id: @investment_snapshot.investor_id, investor_type: @investment_snapshot.investor_type, liq_pref_type: @investment_snapshot.liq_pref_type, liquidation_preference: @investment_snapshot.liquidation_preference, percentage_holding: @investment_snapshot.percentage_holding, price_cents: @investment_snapshot.price_cents, quantity: @investment_snapshot.quantity, spv: @investment_snapshot.spv, status: @investment_snapshot.status, tag: @investment_snapshot.tag, units: @investment_snapshot.units } }
    assert_redirected_to investment_snapshot_url(@investment_snapshot)
  end

  test "should destroy investment_snapshot" do
    assert_difference("InvestmentSnapshot.count", -1) do
      delete investment_snapshot_url(@investment_snapshot)
    end

    assert_redirected_to investment_snapshots_url
  end
end
