# Serves as the base class for all BulkActions
class BulkActionJob < ApplicationJob
  # record_ids: Array of record ids to perform the action on
  # user_id: User id of the user performing the action
  # bulk_action: The action to perform on the records
  # params: Additional parameters to be passed to the action
  def perform(record_ids, user_id, bulk_action, params: {})
    @error_msg = []
    Chewy.strategy(:sidekiq) do
      records = get_class.where(id: record_ids)
      @user = User.find(user_id)
      # Process each record individually, and perform the action on each record
      records.each do |rec|
        Audited.audit_class.as_user(@user) do
          perform_action(rec, user_id, bulk_action, params:)
        end
      end
    end

    # sleep(5)
    if @error_msg.present?
      msg = "#{bulk_action} completed for #{record_ids.count} records, with #{@error_msg.length} errors."
      send_notification("#{msg} Errors will be sent via email", user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg, subject: msg).doc_gen_errors.deliver_now
    else
      msg = "#{bulk_action} completed for #{record_ids.count} records"
      send_notification(msg, user_id, :success)
    end
  end

  def get_class
    raise "Need to override get_class."
  end
end
