# Updates a record, waits for 10 seconds, checks replica
class ReplicationHealthJob < ApplicationJob
  def perform
    Chewy.strategy(:sidekiq) do
      # Update the user
      time = Time.zone.now.to_s
      user.json_fields ||= {}
      user.json_fields["replication_health"] = time
      user.save!

      # Wait for 10 seconds
      sleep(5)

      # Check the replica
      ActiveRecord::Base.connected_to(role: :reading, prevent_writes: true) do
        # This is a temp hack, to read from the replica. Once replication is stable, replace with user
        # Its there cause we read and write from the primary today. See UserReplica however reads from replica (see base class ReplicaRecord)
        user_replica = UserReplica.find(user.id)
        if user_replica.json_fields["replication_health"] == time
          Rails.logger.debug("Replication is Ok")
          user.json_fields["replication_health_status"] = "Ok"
        else
          msg = "Replication is lagging"
          Rails.logger.debug(msg)
          user.json_fields["replication_health_status"] = msg
          ExceptionNotifier.notify_exception(StandardError.new(msg))
        end
      end
      Rails.logger.debug("Replication check completed")
      user.save!
    end
  end

  def replication_health_status
    user.json_fields["replication_health_status"]
  end

  def user
    @user ||= User.joins(:roles).where(roles: { name: 'support' }).first
  end

  def get_timestamp
    user.json_fields["replication_health"]
  end
end
