require "test_helper"

class AllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @allocation = allocations(:one)
  end

  test "should get index" do
    get allocations_url
    assert_response :success
  end

  test "should get new" do
    get new_allocation_url
    assert_response :success
  end

  test "should create allocation" do
    assert_difference("Allocation.count") do
      post allocations_url, params: { allocation: { amount: @allocation.amount, entity_id: @allocation.entity_id, interest_id: @allocation.interest_id, notes: @allocation.notes, offer_id: @allocation.offer_id, quantity: @allocation.quantity, secondary_sale_id: @allocation.secondary_sale_id, verified: @allocation.verified } }
    end

    assert_redirected_to allocation_url(Allocation.last)
  end

  test "should show allocation" do
    get allocation_url(@allocation)
    assert_response :success
  end

  test "should get edit" do
    get edit_allocation_url(@allocation)
    assert_response :success
  end

  test "should update allocation" do
    patch allocation_url(@allocation), params: { allocation: { amount: @allocation.amount, entity_id: @allocation.entity_id, interest_id: @allocation.interest_id, notes: @allocation.notes, offer_id: @allocation.offer_id, quantity: @allocation.quantity, secondary_sale_id: @allocation.secondary_sale_id, verified: @allocation.verified } }
    assert_redirected_to allocation_url(@allocation)
  end

  test "should destroy allocation" do
    assert_difference("Allocation.count", -1) do
      delete allocation_url(@allocation)
    end

    assert_redirected_to allocations_url
  end
end
