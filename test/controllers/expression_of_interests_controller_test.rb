require "test_helper"

class ExpressionOfInterestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @expression_of_interest = expression_of_interests(:one)
  end

  test "should get index" do
    get expression_of_interests_url
    assert_response :success
  end

  test "should get new" do
    get new_expression_of_interest_url
    assert_response :success
  end

  test "should create expression_of_interest" do
    assert_difference("ExpressionOfInterest.count") do
      post expression_of_interests_url, params: { expression_of_interest: { InvestmentOpportunity_id: @expression_of_interest.InvestmentOpportunity_id, allocation_amount_cents: @expression_of_interest.allocation_amount_cents, allocation_percentage: @expression_of_interest.allocation_percentage, amount_cents: @expression_of_interest.amount_cents, approved: @expression_of_interest.approved, entity_id: @expression_of_interest.entity_id, eoi_entity_id: @expression_of_interest.eoi_entity_id, user_id: @expression_of_interest.user_id, verified: @expression_of_interest.verified } }
    end

    assert_redirected_to expression_of_interest_url(ExpressionOfInterest.last)
  end

  test "should show expression_of_interest" do
    get expression_of_interest_url(@expression_of_interest)
    assert_response :success
  end

  test "should get edit" do
    get edit_expression_of_interest_url(@expression_of_interest)
    assert_response :success
  end

  test "should update expression_of_interest" do
    patch expression_of_interest_url(@expression_of_interest), params: { expression_of_interest: { InvestmentOpportunity_id: @expression_of_interest.InvestmentOpportunity_id, allocation_amount_cents: @expression_of_interest.allocation_amount_cents, allocation_percentage: @expression_of_interest.allocation_percentage, amount_cents: @expression_of_interest.amount_cents, approved: @expression_of_interest.approved, entity_id: @expression_of_interest.entity_id, eoi_entity_id: @expression_of_interest.eoi_entity_id, user_id: @expression_of_interest.user_id, verified: @expression_of_interest.verified } }
    assert_redirected_to expression_of_interest_url(@expression_of_interest)
  end

  test "should destroy expression_of_interest" do
    assert_difference("ExpressionOfInterest.count", -1) do
      delete expression_of_interest_url(@expression_of_interest)
    end

    assert_redirected_to expression_of_interests_url
  end
end
