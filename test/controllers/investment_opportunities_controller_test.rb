require "test_helper"

class InvestmentOpportunitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @investment_opportunity = investment_opportunities(:one)
  end

  test "should get index" do
    get investment_opportunities_url
    assert_response :success
  end

  test "should get new" do
    get new_investment_opportunity_url
    assert_response :success
  end

  test "should create investment_opportunity" do
    assert_difference("InvestmentOpportunity.count") do
      post investment_opportunities_url, params: { investment_opportunity: { company_name: @investment_opportunity.company_name, currency: @investment_opportunity.currency, entity_id: @investment_opportunity.entity_id, fund_raise_amount: @investment_opportunity.fund_raise_amount, last_date: @investment_opportunity.last_date, min_ticket_size: @investment_opportunity.min_ticket_size, valuation: @investment_opportunity.valuation } }
    end

    assert_redirected_to investment_opportunity_url(InvestmentOpportunity.last)
  end

  test "should show investment_opportunity" do
    get investment_opportunity_url(@investment_opportunity)
    assert_response :success
  end

  test "should get edit" do
    get edit_investment_opportunity_url(@investment_opportunity)
    assert_response :success
  end

  test "should update investment_opportunity" do
    patch investment_opportunity_url(@investment_opportunity), params: { investment_opportunity: { company_name: @investment_opportunity.company_name, currency: @investment_opportunity.currency, entity_id: @investment_opportunity.entity_id, fund_raise_amount: @investment_opportunity.fund_raise_amount, last_date: @investment_opportunity.last_date, min_ticket_size: @investment_opportunity.min_ticket_size, valuation: @investment_opportunity.valuation } }
    assert_redirected_to investment_opportunity_url(@investment_opportunity)
  end

  test "should destroy investment_opportunity" do
    assert_difference("InvestmentOpportunity.count", -1) do
      delete investment_opportunity_url(@investment_opportunity)
    end

    assert_redirected_to investment_opportunities_url
  end
end
