# frozen_string_literal: true

# Signing CapHive staff in on an ActionDispatch::Integration::Session (OWASP 2026-11 M8).
#
# Since M8, two-factor is required for support and super users from the day it is deployed: a password sign-in by
# one of them stops at the code step (or, with no method yet, at set-up), so a step that posts the sign-in form and
# then requests a page would see a redirect to /users/sign_in instead of the page. Scenarios that act *through* a
# support or super user — rather than testing two-factor itself — sign in with #integration_sign_in, which gives that
# user an authenticator when they have no method and answers the code step, so the session ends signed in as before.
#
# Anyone else (company admins, employees, investors, voluntary-2FA users) is signed in exactly as before: no method
# is added and no code is answered, so scenarios about the code step keep it.
# Same approach as se_sign_in / se_answer_code in security_events_steps.rb.
module RequiredTwoFactorSignIn
  # Posts the sign-in form for `user`; for a support / super user also answers the code step
  # @return [ActionDispatch::Integration::Session] the same session, signed in
  def integration_sign_in(session, user, password: "password")
    # Roles are often added just before signing in: read them fresh
    user.reload
    give_required_authenticator(user)
    session.post "/users/sign_in", params: { user: { email: user.email, password: } }
    answer_required_code(session, user)
    session
  end

  private

  # A required user without a method gets the authenticator app. update_columns, not update!: the test set-up must
  # not record a "two-factor method set" security event or email the firm's admins about it
  def give_required_authenticator(user)
    return unless user.two_factor_required?
    return if user.two_factor_enabled? && user.two_factor_mode.present? && user.otp_secret.present?

    user.update_columns(two_factor_enabled: true, two_factor_mode: "authenticator", otp_secret: User.generate_otp_secret)
  end

  # Answers the code step a required user was sent to; a code already used in this 30-second step is refused
  # (anti-replay, consumed_timestep), so move to the next step first
  def answer_required_code(session, user)
    return unless user.two_factor_required?
    return unless session.response.redirect? && session.response.location.to_s.include?("/two_factor/new")

    user.reload
    travel(31.seconds) if user.consumed_timestep.to_i >= Time.now.to_i / 30
    session.post "/two_factor", params: { otp_code: user.current_otp }
  end
end

World(RequiredTwoFactorSignIn)
