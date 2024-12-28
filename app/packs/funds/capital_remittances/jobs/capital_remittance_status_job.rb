# This job runs daily and marks pending remittances as overdue if required
class CapitalRemittanceStatusJob < BulkActionJob
  queue_as :low

  def perform
    CapitalRemittance.includes(:capital_call).pending.each do |remittance|
      if remittance.capital_call.call_date < Time.zone.today
        remittance.set_status
        remittance.update_column(:status, remittance.status) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
