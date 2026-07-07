class AddEnableNotificationsToDeals < ActiveRecord::Migration[8.1]
  def up
    add_column :deals, :enable_notifications, :boolean, default: true, null: false

    say_with_time "Backfilling deal enable_notifications from json_fields" do
      Deal.reset_column_information

      Deal.unscoped.find_each do |deal|
        next unless deal.json_fields.is_a?(Hash)
        next unless deal.json_fields.key?("enable_notifications")

        legacy_value = ActiveModel::Type::Boolean.new.cast(deal.json_fields["enable_notifications"])

        deal.update_columns(
          enable_notifications: legacy_value,
          json_fields: deal.json_fields.except("enable_notifications")
        )
      end
    end
  end

  def down
    remove_column :deals, :enable_notifications
  end
end
