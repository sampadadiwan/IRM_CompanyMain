class SetupHoldingEntity
  include Interactor

  def call
    Rails.logger.debug "Interactor: SetupHoldingEntity called"
    if context.entity.present?
      setup_holding_entity(context.entity)
    else
      Rails.logger.error "No Entity specified"
      context.fail!(message: "No Entity specified")
    end
  end

  def setup_holding_entity(entity)
    e = Entity.create(name: "#{entity.name} - Employees", entity_type: "Holding",
                      is_holdings_entity: true, active: true, parent_entity_id: entity.id)
    Rails.logger.debug { "Created Employee Holding entity #{e.name} #{e.id} for #{entity.name}" }

    i = Investor.create(investor_name: e.name, investor_entity_id: e.id,
                        entity_id: entity.id, category: "Employee", is_holdings_entity: true)
    Rails.logger.debug { "Created Investor for Employee Holding entity #{i.investor_name} #{i.id} for #{entity.name}" }

    i = Investor.create(investor_name: "#{entity.name} - Founders", investor_entity_id: entity.id,
                        entity_id: entity.id, category: "Founder", is_holdings_entity: true)
    Rails.logger.debug { "Created Investor for Founder Holding entity #{i.investor_name} #{i.id} for #{entity.name}" }

    e = Entity.create(name: "#{entity.name} - Trust", entity_type: "Holding",
                      is_holdings_entity: true, active: true, parent_entity_id: entity.id)
    Rails.logger.debug { "Created Trust entity #{e.name} #{e.id} for #{entity.name}" }

    i = Investor.create(investor_name: "#{entity.name} - ESOP Trust", investor_entity_id: e.id,
                        entity_id: entity.id, category: "Trust", is_holdings_entity: false, is_trust: true)
    Rails.logger.debug { "Created Investor for Trust entity #{i.investor_name} #{i.id} for #{entity.name}" }
  end
end
