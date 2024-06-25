require "application_system_test_case"

class IncomingEmailsTest < ApplicationSystemTestCase
  setup do
    @incoming_email = incoming_emails(:one)
  end

  test "visiting the index" do
    visit incoming_emails_url
    assert_selector "h1", text: "Incoming emails"
  end

  test "should create incoming email" do
    visit incoming_emails_url
    click_on "New incoming email"

    fill_in "Body", with: @incoming_email.body
    fill_in "Entity", with: @incoming_email.entity_id
    fill_in "From", with: @incoming_email.from
    fill_in "Owner", with: @incoming_email.owner_id
    fill_in "Owner type", with: @incoming_email.owner_type
    fill_in "Subject", with: @incoming_email.subject
    fill_in "To", with: @incoming_email.to
    click_on "Create Incoming email"

    assert_text "Incoming email was successfully created"
    click_on "Back"
  end

  test "should update Incoming email" do
    visit incoming_email_url(@incoming_email)
    click_on "Edit this incoming email", match: :first

    fill_in "Body", with: @incoming_email.body
    fill_in "Entity", with: @incoming_email.entity_id
    fill_in "From", with: @incoming_email.from
    fill_in "Owner", with: @incoming_email.owner_id
    fill_in "Owner type", with: @incoming_email.owner_type
    fill_in "Subject", with: @incoming_email.subject
    fill_in "To", with: @incoming_email.to
    click_on "Update Incoming email"

    assert_text "Incoming email was successfully updated"
    click_on "Back"
  end

  test "should destroy Incoming email" do
    visit incoming_email_url(@incoming_email)
    click_on "Destroy this incoming email", match: :first

    assert_text "Incoming email was successfully destroyed"
  end
end
