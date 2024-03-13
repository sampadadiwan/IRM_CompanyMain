class SetupCompany < Trailblazer::Operation
  step :setup_folders
  step :setup_holding_entity

  def setup_folders(_ctx, entity:, **)
    entity.root_folder.presence ||
      Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :regular)
  end

  def setup_holding_entity(ctx, entity:, **)
    result = true

    if entity.entity_type == "Company"
      begin
        setup_employee_holding(entity)
        setup_trust(entity)
      rescue StandardError => e
        Rails.logger.debug e.message
        ctx[:errors] = e.message
        result = false
      end
    end
    result
  end

  def setup_employee_holding(entity)
    e = Entity.where(parent_entity_id: entity.id, name: "#{entity.name} - Employees").first

    unless e
      e = Entity.create!(name: "#{entity.name} - Employees", entity_type: "Holding",
                         is_holdings_entity: true, active: true, parent_entity_id: entity.id, enable_options: true, enable_holdings: true, enable_documents: true, enable_secondary_sale: true)
      Rails.logger.debug { "Created Employee Holding entity #{e.name} #{e.id} for #{entity.name}" }

      i = Investor.create!(investor_name: e.name, investor_entity_id: e.id,
                           entity_id: entity.id, category: "Employee", is_holdings_entity: true)
      Rails.logger.debug { "Created Investor for Employee Holding entity #{i.investor_name} #{i.id} for #{entity.name}" }

      i = Investor.create!(investor_name: "#{entity.name} - Founders", investor_entity_id: entity.id,
                           entity_id: entity.id, category: "Founder", is_holdings_entity: true)
      Rails.logger.debug { "Created Investor for Founder Holding entity #{i.investor_name} #{i.id} for #{entity.name}" }
    end
  end

  def setup_trust(entity)
    e = Entity.where(parent_entity_id: entity.id, name: "#{entity.name} - Trust").first

    unless e
      e = Entity.create!(name: "#{entity.name} - Trust", entity_type: "Holding",
                         is_holdings_entity: true, active: true, parent_entity_id: entity.id, enable_options: true, enable_holdings: true, enable_documents: true, enable_secondary_sale: true)
      Rails.logger.debug { "Created Trust entity #{e.name} #{e.id} for #{entity.name}" }

      i = Investor.create!(investor_name: "#{entity.name} - ESOP Trust", investor_entity_id: e.id,
                           entity_id: entity.id, category: "Trust", is_holdings_entity: false, is_trust: true)
      Rails.logger.debug { "Created Investor for Trust entity #{i.investor_name} #{i.id} for #{entity.name}" }
    end
  end
end
