require "test_helper"

class SignatureWorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @signature_workflow = signature_workflows(:one)
  end

  test "should get index" do
    get signature_workflows_url
    assert_response :success
  end

  test "should get new" do
    get new_signature_workflow_url
    assert_response :success
  end

  test "should create signature_workflow" do
    assert_difference("SignatureWorkflow.count") do
      post signature_workflows_url, params: { signature_workflow: { completed_ids: @signature_workflow.completed_ids, entity_id: @signature_workflow.entity_id, owner_id: @signature_workflow.owner_id, owner_type: @signature_workflow.owner_type, sequential: @signature_workflow.sequential, signatory_ids: @signature_workflow.signatory_ids } }
    end

    assert_redirected_to signature_workflow_url(SignatureWorkflow.last)
  end

  test "should show signature_workflow" do
    get signature_workflow_url(@signature_workflow)
    assert_response :success
  end

  test "should get edit" do
    get edit_signature_workflow_url(@signature_workflow)
    assert_response :success
  end

  test "should update signature_workflow" do
    patch signature_workflow_url(@signature_workflow), params: { signature_workflow: { completed_ids: @signature_workflow.completed_ids, entity_id: @signature_workflow.entity_id, owner_id: @signature_workflow.owner_id, owner_type: @signature_workflow.owner_type, sequential: @signature_workflow.sequential, signatory_ids: @signature_workflow.signatory_ids } }
    assert_redirected_to signature_workflow_url(@signature_workflow)
  end

  test "should destroy signature_workflow" do
    assert_difference("SignatureWorkflow.count", -1) do
      delete signature_workflow_url(@signature_workflow)
    end

    assert_redirected_to signature_workflows_url
  end
end
