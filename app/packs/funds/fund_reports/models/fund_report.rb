class FundReport < ApplicationRecord
  include ForInvestor

  belongs_to :fund
  belongs_to :entity

  STANDARD_COLUMNS = {
    "Id" => "id",
    "Name" => "name",
    "Name Of Scheme" => "name_of_scheme",
    "Start Date" => "start_date",
    "End Date" => "end_date"
  }.freeze

  def to_s
    "#{name}: #{name_of_scheme}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name name_of_scheme entity_id fund_id start_date end_date].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund]
  end
end
