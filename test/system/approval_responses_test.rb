require "application_system_test_case"

class ApprovalResponsesTest < ApplicationSystemTestCase
  setup do
    @approval_response = approval_responses(:one)
  end

  test "visiting the index" do
    visit approval_responses_url
    assert_selector "h1", text: "Approval responses"
  end

  test "should create approval response" do
    visit approval_responses_url
    click_on "New approval response"

    fill_in "Approval", with: @approval_response.approval_id
    fill_in "Entity", with: @approval_response.entity_id
    fill_in "Status", with: @approval_response.status
    click_on "Create Approval response"

    assert_text "Approval response was successfully created"
    click_on "Back"
  end

  test "should update Approval response" do
    visit approval_response_url(@approval_response)
    click_on "Edit this approval response", match: :first

    fill_in "Approval", with: @approval_response.approval_id
    fill_in "Entity", with: @approval_response.entity_id
    fill_in "Status", with: @approval_response.status
    click_on "Update Approval response"

    assert_text "Approval response was successfully updated"
    click_on "Back"
  end

  test "should destroy Approval response" do
    visit approval_response_url(@approval_response)
    click_on "Destroy this approval response", match: :first

    assert_text "Approval response was successfully destroyed"
  end
end
