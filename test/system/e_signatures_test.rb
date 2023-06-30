require "application_system_test_case"

class ESignaturesTest < ApplicationSystemTestCase
  setup do
    @e_signature = e_signatures(:one)
  end

  test "visiting the index" do
    visit e_signatures_url
    assert_selector "h1", text: "E signatures"
  end

  test "should create e signature" do
    visit e_signatures_url
    click_on "New e signature"

    fill_in "Entity", with: @e_signature.entity_id
    fill_in "Label", with: @e_signature.label
    fill_in "Notes", with: @e_signature.notes
    fill_in "Owner", with: @e_signature.owner_id
    fill_in "Owner type", with: @e_signature.owner_type
    fill_in "Sequences", with: @e_signature.sequences
    fill_in "Signature type", with: @e_signature.signature_type
    fill_in "Status", with: @e_signature.status
    fill_in "User", with: @e_signature.user_id
    click_on "Create E signature"

    assert_text "E signature was successfully created"
    click_on "Back"
  end

  test "should update E signature" do
    visit e_signature_url(@e_signature)
    click_on "Edit this e signature", match: :first

    fill_in "Entity", with: @e_signature.entity_id
    fill_in "Label", with: @e_signature.label
    fill_in "Notes", with: @e_signature.notes
    fill_in "Owner", with: @e_signature.owner_id
    fill_in "Owner type", with: @e_signature.owner_type
    fill_in "Sequences", with: @e_signature.sequences
    fill_in "Signature type", with: @e_signature.signature_type
    fill_in "Status", with: @e_signature.status
    fill_in "User", with: @e_signature.user_id
    click_on "Update E signature"

    assert_text "E signature was successfully updated"
    click_on "Back"
  end

  test "should destroy E signature" do
    visit e_signature_url(@e_signature)
    click_on "Destroy this e signature", match: :first

    assert_text "E signature was successfully destroyed"
  end
end
