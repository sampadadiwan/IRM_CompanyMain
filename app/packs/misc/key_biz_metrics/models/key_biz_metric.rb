class KeyBizMetric < ApplicationRecord
  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at display_value metric_type name notes updated_at value].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def to_s
    "#{name}: #{metric_type}: #{value}"
  end
end
