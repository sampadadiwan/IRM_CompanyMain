class DocQuestion < ApplicationRecord
  belongs_to :entity

  def to_s
    tags
  end
end
