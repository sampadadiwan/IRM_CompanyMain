require "application_system_test_case"

class EsignsTest < ApplicationSystemTestCase
  setup do
    @esign = esigns(:one)
  end

  test "visiting the index" do
    visit esigns_url
    assert_selector "h1", text: "Esigns"
  end

  test "should create esign" do
    visit esigns_url
    click_on "New esign"

    check "Completed" if @esign.completed
    fill_in "Entity", with: @esign.entity_id
    fill_in "Link", with: @esign.link
    fill_in "Owner", with: @esign.owner_id
    fill_in "Owner type", with: @esign.owner_type
    fill_in "Reason", with: @esign.reason
    fill_in "Sequence", with: @esign.sequence
    fill_in "Status", with: @esign.status
    fill_in "User", with: @esign.user_id
    click_on "Create Esign"

    assert_text "Esign was successfully created"
    click_on "Back"
  end

  test "should update Esign" do
    visit esign_url(@esign)
    click_on "Edit this esign", match: :first

    check "Completed" if @esign.completed
    fill_in "Entity", with: @esign.entity_id
    fill_in "Link", with: @esign.link
    fill_in "Owner", with: @esign.owner_id
    fill_in "Owner type", with: @esign.owner_type
    fill_in "Reason", with: @esign.reason
    fill_in "Sequence", with: @esign.sequence
    fill_in "Status", with: @esign.status
    fill_in "User", with: @esign.user_id
    click_on "Update Esign"

    assert_text "Esign was successfully updated"
    click_on "Back"
  end

  test "should destroy Esign" do
    visit esign_url(@esign)
    click_on "Destroy this esign", match: :first

    assert_text "Esign was successfully destroyed"
  end
end
