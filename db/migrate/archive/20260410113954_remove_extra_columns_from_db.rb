class RemoveExtraColumnsFromDb < ActiveRecord::Migration[8.1]
  def up
    return if Rails.env.production?

    # Remove foreign keys first
    foreign_keys_to_remove = [
      %i[documents signed_by_id],
      %i[deals deal_documents_folder_id],
      %i[ai_reports entity_id],
      %i[ai_reports report_id],
      %i[fund_sebi_infos entity_id],
      %i[fund_sebi_infos fund_id],
      %i[regulatory_reports entity_id],
      %i[regulatory_reports form_type_id]
    ]

    foreign_keys_to_remove.each do |table, column|
      if foreign_key_exists?(table, column: column)
        puts "Removing foreign key from #{table} on #{column}"
        remove_foreign_key table, column: column
      end
    end

    # Drop tables missing from schema.rb
    tables_to_drop = %i[ai_reports background_jobs fund_sebi_infos regulatory_reports]
    tables_to_drop.each do |table|
      if table_exists?(table)
        puts "Dropping table #{table}"
        drop_table table
      end
    end

    # Remove columns missing from schema.rb
    columns_to_remove = {
      allocation_runs: [:statement_for],
      capital_commitments: [:investor_signature_types],
      capital_distribution_payments: [:other_fee_cents],
      deals: [:deal_documents_folder_id],
      documents: %i[adhaar_esign_completed adhaar_esign_enabled signature_type signed_by_accept signed_by_id],
      e_signatures: %i[deleted_at remind_in signer_id],
      fund_units: [:gp_units],
      funds: %i[fund_signature_types investor_signature_types permissions regulatory_env slug],
      investor_accesses: %i[call_code tags],
      investor_kycs: [:pan_card_data],
      portfolio_investments: [:reference_id],
      stamp_papers: %i[amounts deleted_at doc_ref_id document_category duty_paid_by duty_payer_email_id duty_payer_phone_number duty_payment_method ref_id stamp_type state],
      users: [:lock_version]
    }

    columns_to_remove.each do |table, columns|
      columns.each do |column|
        if column_exists?(table, column)
          puts "Removing column #{column} from table #{table}"
          remove_column table, column
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
