class ComplianceCheck < ApplicationRecord
  belongs_to :entity
  belongs_to :compliance_rule, optional: true
  belongs_to :parent, polymorphic: true
  belongs_to :owner, polymorphic: true

  def to_s
    parent ? "#{parent} - #{owner}" : owner.to_s
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at owner_id owner_type parent_id parent_type status updated_at]
  end
end
