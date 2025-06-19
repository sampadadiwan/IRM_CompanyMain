class AccountEntryDeleteJob < ApplicationJob
  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(params, user_id)
    user = User.find(user_id)
    Chewy.strategy(:sidekiq) do
      # We get a ransack query for the AEs to delete
      @q = AccountEntry.ransack(params[:q])
      # Get the AEs for the query
      @account_entries = AccountEntryPolicy::Scope.new(user, @q.result).resolve
      @account_entries = @account_entries.where(fund_id: params[:fund_id]) if params[:fund_id].present?
      count = @account_entries.count
      Audited.audit_class.as_user(user) do
        @account_entries.each(&:destroy)
      end

      message = "#{count} account entries were deleted by #{user.email}"
      send_notification(message, user_id)
    end
  end
end
