class AmlReportJob < ApplicationJob
  queue_as :serial

  after_perform do |job|
    if job.arguments.second.present?
      investor_kyc = InvestorKyc.find(job.arguments.first)
      UserAlert.new(user_id: job.arguments.second, message: "Aml Report for #{investor_kyc.full_name} has been generated. Please refresh the page to see it", level: "success").broadcast
    end
  end

  def perform(investor_kyc_id, _user_id = nil)
    Chewy.strategy(:sidekiq) do
      investor_kyc = InvestorKyc.find(investor_kyc_id)
      aml_report = AmlReport.create(name: investor_kyc.full_name, investor_kyc_id:, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id)
      aml_report.generate({ year: investor_kyc.birth_date&.year.to_s })
      aml_report.save!
    end
  end
end
