# This module `WithSnapshot` is a concern designed to add snapshot functionality to ActiveRecord models.
# It provides mechanisms to create immutable snapshots of records, ensuring that snapshots cannot be modified
# once created. This is particularly useful for maintaining historical records or audit trails.
#
# ## How it Works
# - **Default Scope**: By default, records with a `snapshot_date` of `nil` are included in queries. This ensures
#   that only the "live" records are fetched unless explicitly overridden.
# - **Scopes**:
#   - `with_snapshots`: Allows fetching all records, including snapshots, by unscoping the default condition.
# - **Callbacks**:
#   - After a record is created, the `orignal_id` is set to the record's `id` if it is not already set. This is #     for new records only.
# - **Readonly Behavior**:
#   - Records with a `snapshot_date` that is not equal to the current date are marked as readonly, ensuring
#     that snapshots cannot be modified.
# - **Snapshot Creation**:
#   - The `snapshot` class method allows creating a snapshot of a given model. It duplicates the model's
#     attributes, assigns the `orignal_id` to the original record's ID, sets the `snapshot_date`, and marks
#     the record as a snapshot.
#
# ## Usage
# - This concern is used in models like `Fund` and `PortfolioInvestment` to manage snapshots of their records.
# - For example, in `Fund`, snapshots are used to preserve historical data for reporting purposes.
# - In `PortfolioInvestment`, snapshots help track changes in investments over time.
#
# ## Related Methods
# - The method `ApplicationController.ransack_with_snapshot` is designed to work with models that include
#   the `WithSnapshot` concern. It provides a way to query both live records and snapshots, enabling
#   flexible reporting and data analysis. Also see FundSnapshotJob

#
# ## Notes
# - The `set_orignal_id` method uses `update_column` to bypass validations and callbacks, which is intentional
#   to ensure the `orignal_id` is set immediately after creation.
# - The `readonly?` method ensures that snapshots remain immutable, preventing accidental modifications.
# 
module WithSnapshot
  extend ActiveSupport::Concern

  included do
    # Default scope to include only records without a snapshot date, ie which are not snapshots
    default_scope { where("#{table_name}.snapshot_date" => nil) }
    scope :with_snapshots, -> { unscope(where: "#{table_name}.snapshot_date") }
    # This ensures new records have an orignal_id set to their id
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
