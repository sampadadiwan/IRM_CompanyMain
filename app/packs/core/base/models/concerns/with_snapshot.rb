module WithSnapshot
  extend ActiveSupport::Concern

  included do
    # scope :without_snapshots, -> { where(snapshot: false) }
    # scope :with_snapshots, -> { where(snapshot: [true, false]) }

    default_scope { where("#{table_name}.snapshot" => false) }
    scope :with_snapshots, -> { unscope(where: "#{table_name}.snapshot") }
    after_create :set_orignal_id, if: -> { orignal_id.nil? }
  end

  # rubocop :disable Rails/SkipsModelValidations
  def set_orignal_id
    update_column(:orignal_id, id) if orignal_id.nil?
  end
  # rubocop :enable Rails/SkipsModelValidations

  # Ensure the snapshot can never be modified
  def readonly?
    snapshot_date.present? && snapshot_date != Time.zone.today
  end

  class_methods do
    def snapshot(model, snapshot_date: nil)
      snapshot_date ||= Time.zone.today
      attributes = model.attributes
      attributes.delete("id")
      attributes["orignal_id"] = model.id
      attributes["snapshot_date"] = snapshot_date
      attributes["snapshot"] = true
      build(attributes)
    end
  end
end
