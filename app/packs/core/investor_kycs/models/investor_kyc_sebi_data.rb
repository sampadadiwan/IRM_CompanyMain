class InvestorKycSebiData < ApplicationRecord
  belongs_to :entity
  belongs_to :investor_kyc, optional: true

  INVESTOR_CATEGORIES = %i[internal domestic foreign other].freeze
  INVESTOR_SUB_CATEGORIES = {
    internal: ["Sponsor", "Manager", "Directors/Partners/Employees of Sponsor", "Directors/Partners/Employees of Manager", "Employee Benefit Trust of Manager"],
    domestic: ["Banks", "NBFCs", "Insurance Companies", "Pension Funds", "Provident Funds", "AIFs", "Other Corporates", "Resident Individuals", "Non-Corporate (other than Trusts)", "Trusts"],
    foreign: ["FPIs", "FVCIs", "NRIs", "Foreign Others"],
    other: ["Domestic Developmental Agencies/Government Agencies", "Others"]
  }.freeze
  NESTED_ATTRIBUTES = %i[id entity_id investor_kyc_id investor_category investor_sub_category].freeze

  validate :investor_sub_category_heirarchy

  def investor_sub_category_heirarchy
    self.investor_category = investor_category&.downcase
    Rails.logger.debug { "investor_category: #{investor_category}, investor_sub_category: #{investor_sub_category}" }
    errors.add(:investor_sub_category, "should be one of #{INVESTOR_SUB_CATEGORIES.stringify_keys[investor_category].join(', ')}") if investor_category.present? && investor_sub_category.present? && INVESTOR_SUB_CATEGORIES.stringify_keys[investor_category]&.exclude?(investor_sub_category)
  end
end
