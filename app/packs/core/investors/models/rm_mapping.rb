class RmMapping < ApplicationRecord
  belongs_to :rm, class_name: "Investor"
  belongs_to :rm_entity, class_name: "Entity"
  belongs_to :investor
  belongs_to :entity

  scope :approved, -> { where(approved: true) }
  scope :unapproved, -> { where(approved: false) }

  flag :permissions, %i[read create update approve generate_docs]

  before_validation :set_rm_entity
  def set_rm_entity
    self.rm_entity_id = rm.investor_entity_id
  end

  def to_s
    "#{rm} => #{investor}"
  end

  def self.investors_for(user, from_entity)
    mappings = from_entity.rm_mappings.where(rm_entity_id: user.entity_id)
    from_entity.investors.joins(:rm_mappings).merge(mappings)
  end
end
