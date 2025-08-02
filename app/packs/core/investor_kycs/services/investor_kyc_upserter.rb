# Service object that either updates or creates an InvestorKyc record,
# depending on whether an ID is passed in the params.
class InvestorKycUpserter
  # Entry point to the service
  # @param params [Hash] - the parameters for the KYC (may contain :id for update)
  # @param current_user [User] - the currently signed-in user
  def self.call(params:, current_user:)
    if params[:id].present?
      # If ID is present, we are updating an existing KYC
      investor_kyc = InvestorKyc.find(params[:id])

      # Determine whether validations can be skipped
      # (e.g., if the user is an investor updating their own KYC in their own entity)
      skip_validation = current_user.curr_role_investor? && investor_kyc.entity_id == current_user.entity_id

      # Assign new attributes to the existing record
      investor_kyc.assign_attributes(params)

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
    OpenStruct.new(success?: result.success?, investor_kyc: investor_kyc, errors: result[:errors])
  end
end
