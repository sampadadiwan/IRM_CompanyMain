class Task < ApplicationRecord
  belongs_to :entity
  belongs_to :investor
  belongs_to :user
end
