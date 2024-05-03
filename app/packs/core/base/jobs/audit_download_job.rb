class AuditDownloadJob < ApplicationJob
  def perform(params, user_id: nil)
    # Get the audits
    @user = User.find(user_id)
    # Ensure we can only download audits that the user has access to
    @audits = AuditPolicy::Scope.new(@user, Audit).resolve
    # Apply the filters
    @audits = @audits.ransack(params[:q]).result.order(id: :desc)

    # Render the XL
    controller = ActionController::Base.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new
    controller.instance_variable_set(:@audits, @audits)
    xl = controller.render_to_string(template: 'audits/index', formats: [:xlsx])

    # Write to a file and then delete it after email
    file = Tempfile.new(['audits', '.xlsx'])
    file.binmode
    file.write(xl)
    file.rewind

    # Email out the XL file
    UserMailer.with(user_id: @user.id, entity_id: @user.entity_id, file:).audit_download.deliver_now

    # Close and delete the file
    file.close
    file.unlink
  end
end
