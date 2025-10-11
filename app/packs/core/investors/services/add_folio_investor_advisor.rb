class AddFolioInvestorAdvisor < Trailblazer::Operation
  AdvisorPresent = Class.new(Trailblazer::Activity::Signal)
  # Step-by-step operation to add an investor advisor for a fund
  # Each step performs a specific task, and errors are handled gracefully.
  step :check_investor_advisor_presence,
       Output(AdvisorPresent, :advisor_present) => Id(:save) # If advisor exists, skip to save step directly - we need to save in case we have added some permissions
  step :fetch_or_create_advisor_entity
  left :handle_entity_errors, Output(:failure) => End(:failure)
  step :fetch_or_create_user
  left :handle_user_create_errors, Output(:failure) => End(:failure)
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :create_access_rights
  left :handle_access_rights_errors, Output(:failure) => End(:failure)
  step :create_investor_access
  left :handle_investor_access_errors, Output(:failure) => End(:failure)

  def check_investor_advisor_presence(ctx, investor_advisor:, params:, **)
    user = User.find_by(email: investor_advisor.email)
    ctx[:user] = user if user.present?

    # If user is not present then IA cannot exist so go to next step
    return true if user.blank?

    # Find existing IA
    existing_advisor = InvestorAdvisor.find_by(entity_id: investor_advisor.entity_id, user_id: user.id)
    return true unless existing_advisor # continue normal path

    # Update permissions if needed
    investor_advisor.permissions.each do |permission|
      existing_advisor.permissions.set(permission)
    end
    %i[investor_kyc_read investor_read].each do |ext_permission|
      existing_advisor.extended_permissions.set(ext_permission)
    end

    ctx[:investor_advisor] = existing_advisor

    # Emit the special output signal AdvisorPresent to jump to the `:save` step
    AdvisorPresent.new
  end

  # Fetches or creates an entity for the investor advisor.
  # If the entity already exists, it returns true.
  def fetch_or_create_advisor_entity(ctx, investor_advisor:, params:, **)
    return true if ctx[:user].present?

    entity_result = CreateInvestorAdvisorEntity.call(name: params[:investor_advisor][:advisor_entity_name], primary_email: investor_advisor.email)
    ctx[:entity] = entity_result[:entity]
    entity_result.success?
  end

  def handle_entity_errors(ctx, **)
    ctx[:errors] = "Entity could not be created. #{ctx[:entity].errors.full_messages.join(', ')}"
    Rails.logger.error ctx[:errors]
    false
  end

  # Fetches an existing user or creates a new one for the investor advisor.
  # Associates the user with the `investor_advisor` object if successful.
  def fetch_or_create_user(ctx, investor_advisor:, params:, **)
    result = FetchOrCreateUser.call(
      email: investor_advisor.email,
      first_name: params[:investor_advisor][:first_name],
      last_name: params[:investor_advisor][:last_name],
      entity_id: ctx[:entity]&.id,
      role: :investor_advisor
    )
    ctx[:adv_user] = result[:user] # Store the user in the context.
    ctx[:create_user_flag] = result[:created_new_user] # Flag to indicate if a new user was created.
    ctx[:user_save_result] = result.success? # Store the success status.
    investor_advisor.user = result[:user] if result.success? # Associate user with the advisor.
    result.success?
  end

  # Handles errors that occur during user creation.
  # Logs the error and sets the error message in the context.
  def handle_user_create_errors(ctx, **)
    ctx[:errors] = "User could not be created. #{ctx[:adv_user].errors.full_messages.join(', ')}"
    Rails.logger.error ctx[:errors]
    false
  end

  # Saves the `investor_advisor` object to the database.
  def save(_ctx, investor_advisor:, **)
    investor_advisor.save
  end

  # Handles validation errors for the `investor_advisor` object.
  # Logs the errors and sets the error message in the context.
  def handle_errors(ctx, investor_advisor:, **)
    unless investor_advisor.valid?
      ctx[:errors] = investor_advisor.errors.full_messages.join(", ")
      Rails.logger.error investor_advisor.errors.full_messages
    end
    investor_advisor.valid?
  end

  # Creates access rights for the investor advisor to the associated fund.
  # Uses the `CreateAccessRightForInvestorAdvisor` service to perform the operation.
  def create_access_rights(ctx, investor_advisor:, fund:, **)
    owner = fund
    result = CreateAccessRightForInvestorAdvisor.call(
      entity_id: investor_advisor.entity_id,
      owner: owner,
      user_id: investor_advisor.user_id,
      access_type: owner.class.name, # Access type is based on the owner's class name.
      metadata: "investor_advisor" # Metadata to indicate the role.
    )
    ctx[:access_right] = result[:access_right] # Store the access right in the context.
    result.success?
  end

  # Handles errors that occur during the creation of access rights.
  # Logs the error and sets the error message in the context.
  def handle_access_rights_errors(ctx, **)
    ctx[:errors] = "Error creating Access Rights: #{ctx[:access_right].errors.full_messages.join(', ')}"
    Rails.logger.error ctx[:errors]
    false
  end

  # Creates investor access for the investor advisor to the associated investor.
  # Uses the `CreateInvestorAccessForInvestorAdvisor` service to perform the operation.
  def create_investor_access(ctx, investor_advisor:, investor:, fund:, **)
    user = investor_advisor.user # The user associated with the investor advisor.
    result = CreateInvestorAccessForInvestorAdvisor.call(
      investor: investor,
      user: user,
      entity_id: fund.entity_id,
      granted_by_user_id: investor_advisor.created_by_id # The user who granted the access.
    )
    ctx[:investor_access] = result[:investor_access] # Store the investor access in the context.
    result.success?
  end

  # Handles errors that occur during the creation of investor access.
  # Logs the error and sets the error message in the context.
  def handle_investor_access_errors(ctx, **)
    ctx[:errors] = "Error creating Investor Access: #{ctx[:investor_access].errors.full_messages.join(', ')}"
    Rails.logger.error ctx[:errors]
    false
  end
end
