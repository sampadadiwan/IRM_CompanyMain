require "application_system_test_case"

class ApprovalsTest < ApplicationSystemTestCase
  setup do
    @approval = approvals(:one)
  end

  test "visiting the index" do
    visit approvals_url
    assert_selector "h1", text: "Approvals"
  end

  test "should create approval" do
    visit approvals_url
    click_on "New approval"

    fill_in "Agreements reference", with: @approval.agreements_reference
    fill_in "Approved count", with: @approval.approved_count
    fill_in "Entity", with: @approval.entity_id
    fill_in "Rejected count", with: @approval.rejected_count
    fill_in "Title", with: @approval.title
    click_on "Create Approval"

    assert_text "Approval was successfully created"
    click_on "Back"
  end

  test "should update Approval" do
    visit approval_url(@approval)
    click_on "Edit this approval", match: :first

    fill_in "Agreements reference", with: @approval.agreements_reference
    fill_in "Approved count", with: @approval.approved_count
    fill_in "Entity", with: @approval.entity_id
    fill_in "Rejected count", with: @approval.rejected_count
    fill_in "Title", with: @approval.title
    click_on "Update Approval"

    assert_text "Approval was successfully updated"
    click_on "Back"
  end

  test "should destroy Approval" do
    visit approval_url(@approval)
    click_on "Destroy this approval", match: :first

    assert_text "Approval was successfully destroyed"
  end
end
