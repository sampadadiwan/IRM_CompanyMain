class Approval < ApplicationRecord
  belongs_to :entity
  has_rich_text :agreements_reference
end
