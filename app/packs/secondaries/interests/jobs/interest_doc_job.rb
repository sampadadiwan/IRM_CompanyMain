class InterestDocJob < DocGenJob
  def templates(_model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model.present?
      model.secondary_sale.documents.templates.where(owner_tag: "Buyer Template")
    else
      @secondary_sale.documents.templates.where(owner_tag: "Buyer Template")
    end
  end

  def models
    if @interest_id.present?
      [Interest.find(@interest_id)]
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
