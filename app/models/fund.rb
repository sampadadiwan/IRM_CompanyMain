class Fund < ApplicationRecord
  belongs_to :entity
  has_many :documents, as: :owner, dependent: :destroy
  monetize :committed_amount_cents, :collected_amount_cents
end
