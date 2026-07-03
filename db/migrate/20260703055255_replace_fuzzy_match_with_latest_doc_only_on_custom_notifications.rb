class ReplaceFuzzyMatchWithLatestDocOnlyOnCustomNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :custom_notifications, :latest_doc_only, :boolean, default: true, null: false

    CustomNotification.where(fuzzy_match: true).where.not(attachment_names: [nil, ""]).find_each do |cn|
      wrapped = cn.attachment_names.split(',').map(&:strip).compact_blank.map { |n| "*#{n}*" }.join(', ')
      cn.update_column(:attachment_names, wrapped)
    end

    remove_column :custom_notifications, :fuzzy_match
  end

  def down
    add_column :custom_notifications, :fuzzy_match, :boolean, default: false, null: false
    remove_column :custom_notifications, :latest_doc_only
  end
end
