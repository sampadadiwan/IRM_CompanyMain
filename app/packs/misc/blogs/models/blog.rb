class Blog < ApplicationRecord
  has_rich_text :content

  validates :tag_list, length: { maximum: 100 }, allow_blank: true
end
