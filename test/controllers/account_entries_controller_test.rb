require "test_helper"

class AccountEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account_entry = account_entries(:one)
  end

  test "should get index" do
    get account_entries_url
    assert_response :success
  end

  test "should get new" do
    get new_account_entry_url
    assert_response :success
  end

  test "should create account_entry" do
    assert_difference("AccountEntry.count") do
      post account_entries_url, params: { account_entry: { amount: @account_entry.amount, capital_commitment_id: @account_entry.capital_commitment_id, entity_id: @account_entry.entity_id, entry_type: @account_entry.entry_type, folio_id: @account_entry.folio_id, fund_id: @account_entry.fund_id, investor_id: @account_entry.investor_id, name: @account_entry.name, notes: @account_entry.notes, reporting_date: @account_entry.reporting_date } }
    end

    assert_redirected_to account_entry_url(AccountEntry.last)
  end

  test "should show account_entry" do
    get account_entry_url(@account_entry)
    assert_response :success
  end

  test "should get edit" do
    get edit_account_entry_url(@account_entry)
    assert_response :success
  end

  test "should update account_entry" do
    patch account_entry_url(@account_entry), params: { account_entry: { amount: @account_entry.amount, capital_commitment_id: @account_entry.capital_commitment_id, entity_id: @account_entry.entity_id, entry_type: @account_entry.entry_type, folio_id: @account_entry.folio_id, fund_id: @account_entry.fund_id, investor_id: @account_entry.investor_id, name: @account_entry.name, notes: @account_entry.notes, reporting_date: @account_entry.reporting_date } }
    assert_redirected_to account_entry_url(@account_entry)
  end

  test "should destroy account_entry" do
    assert_difference("AccountEntry.count", -1) do
      delete account_entry_url(@account_entry)
    end

    assert_redirected_to account_entries_url
  end
end
