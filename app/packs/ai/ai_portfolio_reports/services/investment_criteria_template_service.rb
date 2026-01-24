# Service class for managing InvestmentCriteriaTemplate records.
#
# Encapsulates business logic for creating, updating, and querying investment
# criteria templates. All operations are scoped to the user's entity.

# @example Creating a new template
#   service = InvestmentCriteriaTemplateService.new(current_user)
#   template = service.create(name: "Tech Criteria", criteria: [{name: "ARR", value: ">$1M"}])
#
# @example Listing templates for a user
#   service = InvestmentCriteriaTemplateService.new(current_user)
#   templates = service.list_for_entity
class InvestmentCriteriaTemplateService
  # Initializes the service with a user context.
  #
  # @param user [User] the user who owns the templates
  def initialize(user)
    @user = user
  end

  # Creates a new investment criteria template for the current user.
  #
  # @param name [String] the template name
  # @param criteria [Array<Hash>] array of criteria hashes with :name and :value keys
  # @return [InvestmentCriteriaTemplate] the newly created template
  # @raise [ActiveRecord::RecordInvalid] if validation fails
  def create(name:, criteria:)
    InvestmentCriteriaTemplate.create!(
      name: name,
      criteria: criteria,
      created_by_user: @user,
      entity: @user.entity
    )
  end

  # Updates an existing template with new name and criteria.
  #
  # @param template [InvestmentCriteriaTemplate] the template to update
  # @param name [String] the new template name
  # @param criteria [Array<Hash>] the new criteria array
  # @return [InvestmentCriteriaTemplate] the updated template
  # @raise [ActiveRecord::RecordInvalid] if validation fails
  def update(template, name:, criteria:)
    template.update!(name: name, criteria: criteria)
    template
  end

  # Lists all templates for the current user's entity, ordered by usage.
  #
  # @return [ActiveRecord::Relation<InvestmentCriteriaTemplate>] templates sorted by usage_count desc
  def list_for_entity
    InvestmentCriteriaTemplate.where(entity: @user.entity)
                              .order(usage_count: :desc, created_at: :desc)
  end

  # Increments the usage counter for a template.
  #
  # @param template [InvestmentCriteriaTemplate] the template to update
  # @return [Boolean] true if update succeeded
  def increment_usage(template)
    template.update!(usage_count: template.usage_count + 1)
  end
end
