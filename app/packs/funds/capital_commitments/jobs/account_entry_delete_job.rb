class AccountEntryDeleteJob < ApplicationJob
  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(params, user_id)
    user = User.find(user_id)
    Chewy.strategy(:sidekiq) do
      # We get a ransack query for the AEs to delete
      @q = AccountEntry.ransack(params[:q])
      # Get the AEs for the query
      @account_entries = AccountEntryPolicy::Scope.new(user, @q.result).resolve
      @account_entries = @account_entries.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

      # H7 — decided per fund, never per row: the funds this user may delete entries in. Found from the
      # funds table (never by scanning account_entries), narrowed to the requested fund if any.
      # Tests H7-2, H7-X1, H7-X2 — features/security/account_entries_delete_all.feature
      fund_ids = deletable_fund_ids(user, params[:fund_id])

      count = 0
      Audited.audit_class.as_user(user) do
        # One fund at a time, so every query is bounded by fund_id
        fund_ids.each do |fund_id|
          fund_entries = @account_entries.where(fund_id:)
          count += fund_entries.count
          # find_each keeps ~1000 rows in memory per batch instead of loading the whole
          # result set (which can be an entire import or fund ledger) at once.
          # Safe while destroying: destroy is a paranoia soft-delete, and find_each's
          # keyset pagination on id never revisits rows behind the cursor.
          fund_entries.find_each(&:destroy)
        end
      end

      message = "#{count} account entries were deleted by #{user.email}"
      send_notification(message, user_id)
    end
  end

  private

  # H7 — the ids of the user's own funds (policy_scope(Fund)) where deleting an entry is allowed: the
  # same rule as a single entry's Delete (AccountEntryPolicy#destroy?, i.e. destroy on the fund; every
  # fund for a company admin). A read-only employee gets none, so nothing is deleted (H7-2).
  def deletable_fund_ids(user, fund_id)
    funds = Pundit.policy_scope!(user, Fund)
    funds = funds.where(id: fund_id) if fund_id.present?
    # A fund list is small (unlike the ledger): check each fund with an unsaved entry standing for its rows
    funds.select do |fund|
      AccountEntryPolicy.new(user, AccountEntry.new(fund:, entity_id: fund.entity_id)).destroy?
    end.map(&:id)
  end
end
