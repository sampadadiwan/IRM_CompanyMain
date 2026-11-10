# frozen_string_literal: true

# Who / where-from / which request, read from memory on the request thread — no query (design card ③, D6).
#
# Model callbacks (rolify, User after-commit) never see the request, so the controller is read from
# Audited.store[:current_controller], which Audited::Sweeper already fills around every controller action
# (ActionController::Base and ::API). Hooks that run outside an action — the Warden failure hook — pass
# `request:` explicitly. In a job, the actor is Current.user (restored by ApplicationJob); else the event
# is the system's.
#
# The signed-in user is read WITHOUT running authentication: Devise's current_user would call
# warden.authenticate, which can re-run strategies in the middle of a sign-in. Instead: the controller's
# memoised @current_user (Devise and the bearer-token paths both set it), else the user already in the
# Warden session.
module SecurityEventContext
  # user_agent column limit (E37)
  USER_AGENT_LIMIT = 255
  IP_LIMIT = 45
  REQUEST_ID_LIMIT = 36

  module_function

  # @param request [ActionDispatch::Request, nil] explicit request (Warden hook, API hooks)
  # @return [Hash] ip_address:, user_agent:, request_id:, actor:, impersonator_id:, door:
  def current(request: nil)
    # The controller of the action in progress, when there is one
    controller = Audited.store[:current_controller]
    request ||= controller.try(:request)

    {
      ip_address: request&.remote_ip.to_s.first(IP_LIMIT).presence,
      user_agent: request&.user_agent.to_s.first(USER_AGENT_LIMIT).presence,
      request_id: request&.request_id.to_s.first(REQUEST_ID_LIMIT).presence,
      actor: actor_from(controller, request),
      impersonator_id: impersonator_from(request),
      door: default_door(controller, request)
    }
  end

  # D10 — a one-way HMAC of the lower-cased email, keyed per region, so reviewers can search for an address
  # without the address (or a password typed into the email box) ever being stored.
  # @return [String, nil] 64 hex characters
  def identifier_digest(email)
    # Nothing to digest
    normalised = email.to_s.strip.downcase
    return nil if normalised.empty?

    OpenSSL::HMAC.hexdigest("SHA256", digest_key, normalised)
  end

  def digest_key
    "#{Rails.application.secret_key_base.to_s[0, 32]}security_event"
  end

  # Done by: the controller's signed-in user, else the user in the Warden session, else the job's Current.user
  def actor_from(controller, request)
    # The user an action already resolved (Devise memo, or the bearer-token path's @current_user)
    user = controller.instance_variable_get(:@current_user) if controller
    # The website session's user, read without running any strategy
    user ||= request&.env&.dig("warden")&.user(scope: :user, run_callbacks: false)
    # A job: ApplicationJob restores the enqueuing user here
    user ||= Current.user
    user.is_a?(User) ? user : nil
  rescue StandardError
    nil
  end

  # On behalf of: the CapHive support user behind an impersonated website session (login_as /
  # support magic link set session[:support_user_id]). Bearer-token requests have no session.
  def impersonator_from(request)
    return nil unless request.respond_to?(:session)

    request.session[:support_user_id].presence&.to_i
  rescue StandardError
    nil
  end

  # Door when the hook does not name one: the admin console, the website, or the system (no request)
  def default_door(controller, request)
    return "system" if request.nil?
    return "admin" if controller.class.name.to_s.start_with?("Admin::")

    "web_password"
  end
end
