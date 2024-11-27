require "application_system_test_case"

class ViewedBiesTest < ApplicationSystemTestCase
  setup do
    @viewed_by = viewed_bies(:one)
  end

  test "visiting the index" do
    visit viewed_bies_url
    assert_selector "h1", text: "Viewed bies"
  end

  test "should create viewed by" do
    visit viewed_bies_url
    click_on "New viewed by"

    fill_in "Owner", with: @viewed_by.owner_id
    fill_in "Owner type", with: @viewed_by.owner_type
    fill_in "User", with: @viewed_by.user_id
    click_on "Create Viewed by"

    assert_text "Viewed by was successfully created"
    click_on "Back"
  end

  test "should update Viewed by" do
    visit viewed_by_url(@viewed_by)
    click_on "Edit this viewed by", match: :first

    fill_in "Owner", with: @viewed_by.owner_id
    fill_in "Owner type", with: @viewed_by.owner_type
    fill_in "User", with: @viewed_by.user_id
    click_on "Update Viewed by"

    assert_text "Viewed by was successfully updated"
    click_on "Back"
  end

  test "should destroy Viewed by" do
    visit viewed_by_url(@viewed_by)
    click_on "Destroy this viewed by", match: :first

    assert_text "Viewed by was successfully destroyed"
  end
end
