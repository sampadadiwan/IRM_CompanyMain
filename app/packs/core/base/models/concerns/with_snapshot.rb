module WithSnapshot
  extend ActiveSupport::Concern

  included do
    scope :without_snapshots, -> { where(snapshot: false) }
    scope :with_snapshots, -> { where(snapshot: [true, false]) }

    # default_scope { where("#{table_name}.snapshot" => false) }
    # scope :with_snapshots, -> { unscope(where: "#{table_name}.snapshot") }
  end

  # Ensure the snapshot can never be modified
  def readonly?
    snapshot_date != Time.zone.today
  end

  class_methods do
    def snapshot(model, snapshot_date: Time.zone.today)
      attributes = model.attributes
      attributes.delete("id")
      attributes["orignal_id"] = model.id
      attributes["snapshot_date"] = snapshot_date
      attributes["snapshot"] = true
      build(attributes)
    end
  end
end
