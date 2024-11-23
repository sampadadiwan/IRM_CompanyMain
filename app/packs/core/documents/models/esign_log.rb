class EsignLog < ApplicationRecord
  belongs_to :entity
  belongs_to :document
end
