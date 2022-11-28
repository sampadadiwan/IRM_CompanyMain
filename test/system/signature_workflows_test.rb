require "application_system_test_case"

class SignatureWorkflowsTest < ApplicationSystemTestCase
  setup do
    @signature_workflow = signature_workflows(:one)
  end

  test "visiting the index" do
    visit signature_workflows_url
    assert_selector "h1", text: "Signature workflows"
  end

  test "should create signature workflow" do
    visit signature_workflows_url
    click_on "New signature workflow"

    fill_in "Completed ids", with: @signature_workflow.completed_ids
    fill_in "Entity", with: @signature_workflow.entity_id
    fill_in "Owner", with: @signature_workflow.owner_id
    fill_in "Owner type", with: @signature_workflow.owner_type
    check "Sequential" if @signature_workflow.sequential
    fill_in "Signatory ids", with: @signature_workflow.signatory_ids
    click_on "Create Signature workflow"

    assert_text "Signature workflow was successfully created"
    click_on "Back"
  end

  test "should update Signature workflow" do
    visit signature_workflow_url(@signature_workflow)
    click_on "Edit this signature workflow", match: :first

    fill_in "Completed ids", with: @signature_workflow.completed_ids
    fill_in "Entity", with: @signature_workflow.entity_id
    fill_in "Owner", with: @signature_workflow.owner_id
    fill_in "Owner type", with: @signature_workflow.owner_type
    check "Sequential" if @signature_workflow.sequential
    fill_in "Signatory ids", with: @signature_workflow.signatory_ids
    click_on "Update Signature workflow"

    assert_text "Signature workflow was successfully updated"
    click_on "Back"
  end

  test "should destroy Signature workflow" do
    visit signature_workflow_url(@signature_workflow)
    click_on "Destroy this signature workflow", match: :first

    assert_text "Signature workflow was successfully destroyed"
  end
end
