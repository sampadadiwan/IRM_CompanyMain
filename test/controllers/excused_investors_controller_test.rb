require "test_helper"

class ExcusedInvestorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @excused_investor = excused_investors(:one)
  end

  test "should get index" do
    get excused_investors_url
    assert_response :success
  end

  test "should get new" do
    get new_excused_investor_url
    assert_response :success
  end

  test "should create excused_investor" do
    assert_difference("ExcusedInvestor.count") do
      post excused_investors_url, params: { excused_investor: { aggregate_portfolio_investment_id: @excused_investor.aggregate_portfolio_investment_id, entity_id: @excused_investor.entity_id, folio_id: @excused_investor.folio_id, fund_id: @excused_investor.fund_id, notes: @excused_investor.notes, portfolio_company_id: @excused_investor.portfolio_company_id, portfolio_investment_id: @excused_investor.portfolio_investment_id } }
    end

    assert_redirected_to excused_investor_url(ExcusedInvestor.last)
  end

  test "should show excused_investor" do
    get excused_investor_url(@excused_investor)
    assert_response :success
  end

  test "should get edit" do
    get edit_excused_investor_url(@excused_investor)
    assert_response :success
  end

  test "should update excused_investor" do
    patch excused_investor_url(@excused_investor), params: { excused_investor: { aggregate_portfolio_investment_id: @excused_investor.aggregate_portfolio_investment_id, entity_id: @excused_investor.entity_id, folio_id: @excused_investor.folio_id, fund_id: @excused_investor.fund_id, notes: @excused_investor.notes, portfolio_company_id: @excused_investor.portfolio_company_id, portfolio_investment_id: @excused_investor.portfolio_investment_id } }
    assert_redirected_to excused_investor_url(@excused_investor)
  end

  test "should destroy excused_investor" do
    assert_difference("ExcusedInvestor.count", -1) do
      delete excused_investor_url(@excused_investor)
    end

    assert_redirected_to excused_investors_url
  end
end
