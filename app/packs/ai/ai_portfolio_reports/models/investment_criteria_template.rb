# Stores reusable investment criteria templates for AI portfolio report generation.
#
# Each template contains a set of named criteria that can be applied when evaluating
# investments against user-defined standards. Templates are user-scoped and track
# usage frequency for sorting purposes.
#
# @!attribute name
#   @return [String] the display name of the template
# @!attribute criteria
#   @return [Array<Hash>] array of criteria hashes with :name and :value keys
# @!attribute usage_count
#   @return [Integer] number of times this template has been applied
# @!attribute created_by_user_id
#   @return [Integer] foreign key to the owning User
class InvestmentCriteriaTemplate < ApplicationRecord
  belongs_to :created_by_user, class_name: 'User'

  validates :name, presence: true
  validates :criteria, presence: true
  validate :criteria_has_at_least_one_item

  # Returns the template name with usage statistics appended.
  #
  # @return [String] formatted name with usage count
  # @example
  #   template.name_with_usage #=> "Growth Criteria (used 5 times)"
  def name_with_usage
    "#{name} (used #{usage_count} times)"
  end

  private

  # Validates that the criteria array contains at least one item.
  #
  # @return [void]
  def criteria_has_at_least_one_item
    return if criteria.blank?
    return if criteria.is_a?(Array) && criteria.any?

    errors.add(:criteria, "must have at least one criterion")
  end
end
