class Audit < Audited::Audit
  def self.ransackable_attributes(_auth_object = nil)
    %w[action associated_id associated_type auditable_id auditable_type audited_changes comment created_at user_id username]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
