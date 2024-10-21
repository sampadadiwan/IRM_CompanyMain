class CreateDeal < DealActions
  step :active_deal, Output(:failure) => End(:failure)
  step :create_activity_template
  step :create_deal_documents_folder
  left :handle_errors, Output(:failure) => End(:failure)

  def active_deal(ctx, deal:, **)
    if deal.save
      deal.entity.active_deal_id = deal.id
      deal.entity.save
    else
      Rails.logger.error deal.errors.full_messages
      ctx[:errors] = deal.errors.full_messages.join(", ")
      false
    end
  end

  def create_activity_template(ctx, deal:, **)
    seq = 1
    ret_val = true
    begin
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
        template_configs = deal.entity.is_fund? ? Deal::FUND_ACTIVITIES : Deal::ACTIVITIES
        template_configs.each do |title, days|
          # Note that if deal_investor_id = nil then this is a template
          DealActivity.create!(deal_id: deal.id, deal_investor_id: nil, status: "Template",
                               entity_id: deal.entity_id, title:, sequence: seq, days: days.to_i)
          seq += 1
        end
      end
    rescue StandardError => e
      Rails.logger.error e.message
      Rails.logger.error e.backtrace
      ctx[:errors] = e.message
      ret_val = false
    end

    ret_val
  end
end
