class AddTransferToFundUnits < ActiveRecord::Migration[7.1]
  def change
    ActiveRecord::Base.transaction do

      unless column_exists?(:fund_units, :transfer)
        add_column :fund_units, :transfer, :string, limit: 8
      end
      FundUnit.where("reason LIKE '%Transfer from%'").includes(:capital_commitment).each do |fu|
        # sample reason -Transfer from 68234959 to SRK1
        # first cehck that after split the length is 5
        # and one of the folio id matches the fu.capital_commitment.folio_id
        # if fu.capital_commitment.folio_id matches the 3rd word in the reason, then it is a transfer out , if it matches the last word, then it is a transfer in
        Rails.logger.info { "Updating transfer for fund unit #{fu.id}" }
        reason = fu.reason.split
        if reason.length == 5
          if reason[2].strip.casecmp?(fu.capital_commitment.folio_id.strip)
            fu.update(transfer: "out")
          elsif reason[4].strip.casecmp?(fu.capital_commitment.folio_id.strip)
            fu.update(transfer: "in")
          end
        else
          Rails.logger.error { "Reason length not 5 words for fund unit #{fu.id} - #{reason}" }
        end
      end
    end

  end
end
