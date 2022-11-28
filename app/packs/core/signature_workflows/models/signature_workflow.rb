class SignatureWorkflow < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :entity

  serialize :signatory_ids, Array
  serialize :completed_ids, Array
  serialize :state, Hash

  validate :owner_interface

  def owner_interface
    errors.add(:owner, "does not implement method signing_link") unless owner.respond_to?(:signing_link)
  end

  def next_step
    pending = (signatory_ids - completed_ids)
    if pending.present?
      send_notification(pending[0])
      self.completed = false
    else
      self.completed = true
      Rails.logger.debug { "SignatureWorkflow #{id} is complete." }
    end
    save
  end

  def send_notification(user_id)
    # Send the notification & update state
    SignatureWorkflowMailer.with(id:, user_id:).notify_signature_required.deliver_later
    update_notification_state(user_id)
  end

  def update_notification_state(user_id)
    # state ||= {}
    state[user_id] ||= {}
    state[user_id]["Notification"] ||= 0
    state[user_id]["Completed"] ||= false
    state[user_id]["Notification"] += 1
    self.status = "Sent #{state[user_id]['Notification'].ordinalize} notification for user #{user_id}"
  end

  def mark_completed(user_id)
    if completed
      Rails.logger.debug { "SignatureWorkflow #{id} is complete." }
    else
      # Send the notification & update state
      SignatureWorkflowMailer.with(id:, user_id:).notify_signature_completed.deliver_later
      update_completion_state(user_id)
      save
      # Trigger the next step
      next_step
    end
  end

  def update_completion_state(user_id)
    # state ||= {}
    state[user_id] ||= {}
    state[user_id]["Completed"] = true
    self.status = "Signature completed for user #{user_id}"
    completed_ids << user_id
    self.completed_ids = completed_ids.to_set.to_a
  end

  def reset
    self.completed_ids = []
    self.state = {}
    self.status = ""
    self.completed = false
    save
  end
end
