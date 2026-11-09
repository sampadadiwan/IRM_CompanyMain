# Service object that either updates or creates an InvestorKyc record,
# depending on whether an ID is passed in the params.
class InvestorKycUpserter
  # Callers access .success?, .investor_kyc, .errors, and also result[:errors] (bracket form).
  # Struct covers all: method readers, symbol bracket access via Struct#[], and success?
  # is defined explicitly because Struct doesn't generate ? predicates for boolean members.
  KycUpsertResult = Struct.new(:success, :investor_kyc, :errors) do
    def success? = success
  end
  # Entry point to the service
  # @param params [Hash] - the parameters for the KYC (may contain :id for update)
  # @param current_user [User] - the currently signed-in user
  # @param bank_change_source [String] - how the save was made, for the M14 bank change guard ("screen")
  def self.call(params:, current_user:, bank_change_source: "screen")
    if params[:id].present?
      # If ID is present, we are updating an existing KYC
      investor_kyc = InvestorKyc.find(params[:id])

      # Determine whether validations can be skipped
      # (e.g., if the user is an investor updating their own KYC in their own entity)
      skip_validation = current_user.curr_role_investor? && investor_kyc.entity_id == current_user.entity_id

      # Assign new attributes to the existing record
      investor_kyc.assign_attributes(params)
      # M14 E9 — a verified KYC can change here (compare_kyc_datas? does not check verified): tag the save
      investor_kyc.bank_change_actor = current_user
      investor_kyc.bank_change_source = bank_change_source

      # Call update service with proper context
      result = InvestorKycUpdate.call(
        investor_kyc: investor_kyc,
        investor_user: skip_validation,
        phone: params[:phone]
      )

      # Return result using OpenStruct for uniform return structure
    else
      # If ID is not present, we are creating a new KYC
      investor_kyc = InvestorKyc.new(params)
      investor_kyc.bank_change_actor = current_user
      investor_kyc.bank_change_source = bank_change_source

      # Determine whether validations can be skipped
      skip_validation = current_user.curr_role_investor? && investor_kyc.entity_id == current_user.entity_id

      # Validate all attached documents manually (prior to creation)
      investor_kyc.documents.each(&:validate)

      # Call create service
      result = InvestorKycCreate.call(
        investor_kyc: investor_kyc,
        investor_user: skip_validation,
        owner_id: params[:owner_id],
        owner_type: params[:owner_type],
        phone: params[:phone]
      )

      # Return result using OpenStruct
    end
    KycUpsertResult.new(result.success?, investor_kyc, result[:errors])
  end
end
