class FundReport < ApplicationRecord
  include ForInvestor

  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :entity

  validates :name, length: { maximum: 50 }, allow_blank: true

  STANDARD_COLUMNS = {
    "Id; num-col" => "id; num-col",
    "Name; text-col" => "name; text-col",
    "Name Of Scheme; text-col" => "name_of_scheme; text-col",
    "Start Date; date-col" => "start_date; date-col",
    "End Date; date-col" => "end_date; date-col"
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
