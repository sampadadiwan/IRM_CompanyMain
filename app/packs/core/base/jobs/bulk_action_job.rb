# Serves as the base class for all BulkActions
class BulkActionJob < ApplicationJob
  queue_as :low

  def perform(record_ids, user_id, bulk_action)
    @error_msg = []
    Chewy.strategy(:sidekiq) do
      investor_kycs = get_class.where(id: record_ids)
      user = User.find(user_id)
      investor_kycs.each do |kyc|
        Audited.audit_class.as_user(user) do
          perform_action(kyc, user_id, bulk_action)
        end
      end
    end

    sleep(5)
    if @error_msg.present?
      msg = "#{bulk_action} completed for #{record_ids.count} records, with #{@error_msg.length} errors. Errors will be sent via email"
      send_notification(msg, user_id, :danger)
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).doc_gen_errors.deliver_now
    else
      msg = "#{bulk_action} completed for #{record_ids.count} records"
      send_notification(msg, user_id, :success)
    end
  end

  def get_class
    raise "Need to override get_class."
  end
end
