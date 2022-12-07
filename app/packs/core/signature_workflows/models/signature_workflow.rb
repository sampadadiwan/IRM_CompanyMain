class SignatureWorkflow < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :entity
  belongs_to :document, optional: true

  serialize :state, Hash

  scope :not_completed, -> { where(completed: false) }
  scope :not_paused, -> { where(paused: false) }

  def signatory_ids
    owner.esigns.where(document_id:)
  end

  def completed_ids
    owner.esigns.where(document_id:).completed
  end

  def pending
    owner.esigns.where(document_id:).not_completed
  end

  def next_step
    if paused
      Rails.logger.debug { "SignatureWorkflow #{id} is paused." }
    else
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

  def send_notification(esign)
    if should_notify?(esign.user_id)
      # Send the notification & update state
      SignatureWorkflowMailer.with(id:, esign_id: esign.id).notify_signature_required.deliver_later
      update_notification_state(esign.user_id)
    else
      Rails.logger.debug { "Skipping send_notification for #{esign.user_id}. Already notified at #{state[esign.user_id]['NotificationTime']}" }
    end
  end

  def should_notify?(user_id)
    state[user_id].blank? ||
      state[user_id]["NotificationTime"].blank? ||
      state[user_id]["NotificationTime"] < 6.hours.ago
  end

  def update_notification_state(user_id)
    state[user_id] ||= {}
    state[user_id]["Notification"] ||= 0
    state[user_id]["Completed"] ||= false
    state[user_id]["Notification"] += 1
    state[user_id]["NotificationTime"] = Time.zone.now
    self.status = "Sent #{state[user_id]['Notification'].ordinalize} notification for user #{user_id}"

    if state[user_id]["Notification"] > 2
      self.status = "Paused! User #{user_id} has not signed"
      self.paused = true
    end

    owner.esigns.where(user_id:).update(status:)
  end

  def mark_completed(user_id)
    if completed
      Rails.logger.debug { "SignatureWorkflow #{id} is complete." }
    elsif owner.esigns.where(user_id:, document_id:, completed: true).present?
      esign = owner.esigns.where(user_id:, document_id:).first
      # Send the notification & update state
      SignatureWorkflowMailer.with(id:, esign_id: esign.id).notify_signature_completed.deliver_later
      update_completion_state(user_id)
      save
      # Trigger the next step
      next_step
    else
      Rails.logger.debug { "SignatureWorkflow: Esign for #{user_id} is not complete in DB." }
    end
  end

  def update_completion_state(user_id)
    state[user_id] ||= {}
    state[user_id]["Completed"] = true
    self.status = "Signature completed for user #{user_id}"
    self.paused = false
    owner.esigns.where(user_id:).update(status:)
  end

  def reset
    self.state = {}
    self.status = ""
    self.completed = false
    self.paused = false
    save
    owner.esigns.where(user_id:).update(status:)
  end
end
