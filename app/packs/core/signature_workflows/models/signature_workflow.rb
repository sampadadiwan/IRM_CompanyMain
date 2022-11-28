class SignatureWorkflow < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :entity

  serialize :signatory_ids, Array
  serialize :completed_ids, Array
  serialize :state, Hash

  def next_step
    if paused
      Rails.logger.debug { "SignatureWorkflow #{id} is paused." }
    else
      pending = (signatory_ids - completed_ids)
      if pending.present?
        # Send notification to the next pending signatory
        send_notification(pending[0])
        self.completed = false
      else
        # No one is pending - its completed
        self.completed = true
        Rails.logger.debug { "SignatureWorkflow #{id} is complete." }
      end
      save
    end
  end

  def send_notification(user_id)
    # Send the notification & update state
    SignatureWorkflowMailer.with(id:, user_id:).notify_signature_required.deliver_later
    update_notification_state(user_id)
  end

  def update_notification_state(user_id)
    state[user_id] ||= {}
    state[user_id]["Notification"] ||= 0
    state[user_id]["Completed"] ||= false
    state[user_id]["Notification"] += 1
    self.status = "Sent #{state[user_id]['Notification'].ordinalize} notification for user #{user_id}"

    if state[user_id]["Notification"] > 2
      self.status = "Paused! User #{user_id} has not signed"
      self.paused = true
    end
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
    state[user_id] ||= {}
    state[user_id]["Completed"] = true
    self.status = "Signature completed for user #{user_id}"
    self.paused = false
    completed_ids << user_id
    self.completed_ids = completed_ids.to_set.to_a
  end

  def reset
    self.completed_ids = []
    self.state = {}
    self.status = ""
    self.completed = false
    self.paused = false
    save
  end
end
