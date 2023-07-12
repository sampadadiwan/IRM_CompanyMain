class ESignature < ApplicationRecord
  belongs_to :entity
  # If the user is nil, then its a template for use, which is filled in by the owner
  belongs_to :user, optional: true
  # Is the offer, commitment etc whose document needs to be signed
  belongs_to :owner, polymorphic: true
  acts_as_list scope: :owner

  before_validation :setup_entity
  def setup_entity
    self.entity_id = owner.entity_id
  end

  before_save :update_status
  def update_status
    self.status = nil if signature_type_changed?
  end

  after_save :update_owner
  def update_owner
    owner.signature_enabled = true
    owner.save
  end

  def add_api_update(update_data)
    if api_updates.present?
      api_updates + update_data.to_s
    else
      self.api_updates = update_data.to_s
    end
  end
end
