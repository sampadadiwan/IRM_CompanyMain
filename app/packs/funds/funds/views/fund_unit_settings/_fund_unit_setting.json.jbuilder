# carry, gp_units, isin and import_upload_id: every column a FundUnitSetting import writes, so an upload can be read back
json.extract! fund_unit_setting, :id, :entity_id, :fund_id, :name, :management_fee, :setup_fee, :carry, :gp_units, :isin,
              :import_upload_id, :created_at, :updated_at
json.url fund_unit_setting_url(fund_unit_setting, format: :json)
