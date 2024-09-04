class GridViewPreference < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :custom_grid_view, optional: true
  acts_as_list column: :sequence, scope: :owner
  validates :key, presence: true

  def self.get_column_name(parent, key)
    begin
      column_name = parent.name.constantize::STANDARD_COLUMNS.key(key)
    rescue NameError
      column_name = parent.model.constantize::STANDARD_COLUMNS.key(key)
    end
    return column_name if column_name.present?

    key.gsub("custom_fields.", "").humanize
  end
end
