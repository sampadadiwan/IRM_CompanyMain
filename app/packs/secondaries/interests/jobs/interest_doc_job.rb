class InterestDocJob < DocGenJob
  # H15 / M9: every template comes from this sale's own Buyer Templates. A template id from another
  # sale or firm finds nothing ("No templates found"), so it can neither render that firm's template
  # nor delete this interest's same-named generated documents. This also removes the NameError the
  # old `elsif model.present?` raised (the argument was `_model`) whenever no template id was given.
  # Tests H15-3, H15-4 — features/security/secondaries_isolation.feature
  def templates(_model = nil)
    # The sale's Buyer Templates; the interest is always in this sale (see models)
    sale_templates = @secondary_sale.documents.templates.where(owner_tag: "Buyer Template")
    # One template the user picked - looked up inside the sale, never by bare id
    @template_id.present? ? sale_templates.where(id: @template_id) : sale_templates
  end

  # H15: the interest is looked up inside the sale the job was given
  def models
    if @interest_id.present?
      @secondary_sale.interests.where(id: @interest_id)
    else
      @secondary_sale.interests.short_listed
    end
  end

  def validate(interest)
    return false, "No Interest found" if interest.blank?
    return false, "Interest not short listed" unless interest.short_listed

    [true, ""]
  end

  def generator
    InterestDocGenerator
  end

  def cleanup_previous_docs(model, template)
    # Delete any existing signed documents
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  # This is idempotent, we should be able to call it multiple times for the same Interest
  def perform(secondary_sale_id, interest_id, user_id, template_id: nil)
    @interest_id = interest_id
    @secondary_sale_id = secondary_sale_id
    @secondary_sale = SecondarySale.find(@secondary_sale_id)
    @template_id = template_id

    @start_date = Time.zone.now
    @end_date = Time.zone.now
    @user_id = user_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    @error_msg
  end
end
