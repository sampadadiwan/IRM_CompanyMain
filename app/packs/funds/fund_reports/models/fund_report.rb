class FundReport < ApplicationRecord
  belongs_to :fund
  belongs_to :entity

  def to_s
    "#{name}: #{name_of_scheme}"
  end
end
