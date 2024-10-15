class AllocationSpaJob < DocGenJob
  def templates(model = nil)
    if @template_id.present?
      [Document.find(@template_id)]
    elsif model && model.custom_fields.docs_to_generate.present?
      # In special cases there is a custom field in the offer, docs_to_generate, that specifies which documents to generate. This is to enable some allocations to have only one doc generated, but others to have more than one doc. E.x if the shares are in DEMAT, then only SPA needs to be generated, if not then SPA and another doc needs to be generated.
      template_names = model.custom_fields.docs_to_generate.split(",").map(&:strip)
      Rails.logger.debug { "AllocationSpaJob: Generating only docs_to_generate #{template_names}" }
      model.secondary_sale.documents.where(owner_tag: "Allocation Template").where(name: template_names)
    else
      Rails.logger.debug "AllocationSpaJob: Generating all Allocation Templates"
      @secondary_sale.documents.where(owner_tag: "Allocation Template")
    end
  end

  def models
    if @allocation_id.present?
      [Allocation.find(@allocation_id)]
    else
      @secondary_sale.allocations.verified
    end
  end

  def validate(allocation)
    return false, "No Allocation found" if allocation.blank?
    return false, "Allocation not verified" unless allocation.verified

    [true, ""]
  end

  def generator
    AllocationSpaGenerator
  end

  def cleanup_previous_docs(model, template)
    model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def perform(secondary_sale_id, allocation_id, user_id, template_id: nil)
    @secondary_sale_id = secondary_sale_id
    @secondary_sale = SecondarySale.find(@secondary_sale_id)

    @allocation_id = allocation_id
    @user_id = user_id
    @template_id = template_id

    @start_date = Time.zone.now
    @end_date = Time.zone.now

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id) if valid_inputs
    end

    @error_msg
  end
end
