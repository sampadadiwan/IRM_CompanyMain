class FundBase < ApplicationRecord
  self.abstract_class = true
  acts_as_favoritable
  include ForInvestor
  include WithCustomField

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze
  REMITTANCE_GENERATION_BASIS = ["Folio Amount", "Fund Amount"].freeze
end
