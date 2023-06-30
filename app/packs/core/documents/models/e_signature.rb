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

  after_save :update_owner
  def update_owner
    owner.signature_enabled = true
    owner.save
  end
end
