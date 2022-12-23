class CreateActivityTemplate
  include Interactor

  def call
    Rails.logger.debug "Interactor: CreateActivityTemplate called"
    if context.deal.present?
      create_activity_template(context.deal)
    else
      Rails.logger.error "No Deal specified"
      context.fail!(message: "No Deal specified")
    end
  end

  def create_activity_template(deal)
    seq = 1
    # Sometimes we clone the templates of prev customized deals
    if deal.clone_from_id.present?
      clone_from = Deal.find(deal.clone_from_id)
      templates = DealActivity.templates(clone_from)
      templates.each do |template|
        # Note that if deal_investor_id = nil then this is a template
        DealActivity.create!(deal_id: deal.id, deal_investor_id: nil, status: "Template",
                             entity_id: deal.entity_id, title: template.title, sequence: seq, days: template.days)
        seq += 1
      end
    else
      # Sometimes we use the templates specified in env file
      template_configs = deal.entity.entity_type == "Investment Fund" ? Deal::FUND_ACTIVITIES : Deal::ACTIVITIES
      template_configs.each do |title, days|
        # Note that if deal_investor_id = nil then this is a template
        DealActivity.create!(deal_id: deal.id, deal_investor_id: nil, status: "Template",
                             entity_id: deal.entity_id, title:, sequence: seq, days: days.to_i)
        seq += 1
      end
    end
  end
end
