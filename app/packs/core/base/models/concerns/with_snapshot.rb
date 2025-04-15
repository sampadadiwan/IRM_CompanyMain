module WithSnapshot
  extend ActiveSupport::Concern

  included do
    # This code runs in the context of the class that includes the module
    self.primary_key = %i[id snapshot_date]
    before_create :set_default_snapshot_date
  end

  # Setup the snapshot_date to be today's date
  def set_default_snapshot_date
    self.snapshot_date ||= Time.zone.today
  end

  # Ensure the snapshot can never be modified
  def readonly?
    false
  end

  class_methods do
    def snapshot(model)
      attributes = model.attributes
      # The primary_key is a composite key, so we need to set the snapshot_date
      attributes["id"] = [model.id, Time.zone.today]
      create(attributes)
    end
  end
end
