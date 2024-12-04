class GridViewPreference < ApplicationRecord
  belongs_to :owner, polymorphic: true
  acts_as_list column: :sequence, scope: :owner
  validates :key, presence: true

  after_save :touch_entity
  after_destroy :touch_entity

  def self.get_column_name(parent, key)
    begin
      column_name = parent.name.constantize::STANDARD_COLUMNS.key(key)
    rescue NameError
      column_name = parent.model.constantize::STANDARD_COLUMNS.key(key)
    end
    return column_name if column_name.present?

    key.gsub("custom_fields.", "").humanize
  end

  private

  def touch_entity
    if owner.is_a?(FormType) && owner.entity.present?
      owner.entity.touch
    end
  end
end
