class Report < ApplicationRecord
  belongs_to :entity, optional: true
  belongs_to :user
end
