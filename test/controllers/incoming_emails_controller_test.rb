require "test_helper"

class IncomingEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @incoming_email = incoming_emails(:one)
  end

  test "should get index" do
    get incoming_emails_url
    assert_response :success
  end

  test "should get new" do
    get new_incoming_email_url
    assert_response :success
  end

  test "should create incoming_email" do
    assert_difference("IncomingEmail.count") do
      post incoming_emails_url, params: { incoming_email: { body: @incoming_email.body, entity_id: @incoming_email.entity_id, from: @incoming_email.from, owner_id: @incoming_email.owner_id, owner_type: @incoming_email.owner_type, subject: @incoming_email.subject, to: @incoming_email.to } }
    end

    assert_redirected_to incoming_email_url(IncomingEmail.last)
  end

  test "should show incoming_email" do
    get incoming_email_url(@incoming_email)
    assert_response :success
  end

  test "should get edit" do
    get edit_incoming_email_url(@incoming_email)
    assert_response :success
  end

  test "should update incoming_email" do
    patch incoming_email_url(@incoming_email), params: { incoming_email: { body: @incoming_email.body, entity_id: @incoming_email.entity_id, from: @incoming_email.from, owner_id: @incoming_email.owner_id, owner_type: @incoming_email.owner_type, subject: @incoming_email.subject, to: @incoming_email.to } }
    assert_redirected_to incoming_email_url(@incoming_email)
  end

  test "should destroy incoming_email" do
    assert_difference("IncomingEmail.count", -1) do
      delete incoming_email_url(@incoming_email)
    end

    assert_redirected_to incoming_emails_url
  end
end
