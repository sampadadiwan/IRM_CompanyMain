require "application_system_test_case"

class AllocationsTest < ApplicationSystemTestCase
  setup do
    @allocation = allocations(:one)
  end

  test "visiting the index" do
    visit allocations_url
    assert_selector "h1", text: "Allocations"
  end

  test "should create allocation" do
    visit allocations_url
    click_on "New allocation"

    fill_in "Amount", with: @allocation.amount
    fill_in "Entity", with: @allocation.entity_id
    fill_in "Interest", with: @allocation.interest_id
    fill_in "Notes", with: @allocation.notes
    fill_in "Offer", with: @allocation.offer_id
    fill_in "Quantity", with: @allocation.quantity
    fill_in "Secondary sale", with: @allocation.secondary_sale_id
    check "Verified" if @allocation.verified
    click_on "Create Allocation"

    assert_text "Allocation was successfully created"
    click_on "Back"
  end

  test "should update Allocation" do
    visit allocation_url(@allocation)
    click_on "Edit this allocation", match: :first

    fill_in "Amount", with: @allocation.amount
    fill_in "Entity", with: @allocation.entity_id
    fill_in "Interest", with: @allocation.interest_id
    fill_in "Notes", with: @allocation.notes
    fill_in "Offer", with: @allocation.offer_id
    fill_in "Quantity", with: @allocation.quantity
    fill_in "Secondary sale", with: @allocation.secondary_sale_id
    check "Verified" if @allocation.verified
    click_on "Update Allocation"

    assert_text "Allocation was successfully updated"
    click_on "Back"
  end

  test "should destroy Allocation" do
    visit allocation_url(@allocation)
    click_on "Destroy this allocation", match: :first

    assert_text "Allocation was successfully destroyed"
  end
end
