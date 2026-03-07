class ResetAccessRightsCacheJob < ApplicationJob
  queue_as :default

  def perform(user_id, current_user_id)
    Chewy.strategy(:atomic) do
      user = User.find(user_id)
      user.reset_access_rights_cache
      send_notification("Access rights cache for #{user.name} has been reset successfully.", current_user_id)
    end
  rescue StandardError => e
    send_notification("Failed to reset access rights cache for #{user&.name || user_id}: #{e.message}", current_user_id, "danger")
    raise e
  end
end
