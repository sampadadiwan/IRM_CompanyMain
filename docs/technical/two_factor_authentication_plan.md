# Two-Factor Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add TOTP-based 2FA using `devise-two-factor` gem, supporting authenticator apps and WhatsApp delivery.

**Architecture:** Lightweight integration with `devise-two-factor` gem. Columns on `users` table. New `Users::TwoFactorController` for enrollment and verification. Existing `SessionsController` and `UsersController#no_password_login` modified to intercept for 2FA. WhatsApp delivery via existing `WhatsappGeneralNotification` infrastructure.

**Tech Stack:** Rails 7+, Devise, devise-two-factor, rotp, RQRCode (for QR codes), RSpec, Cucumber

**Design Doc:** `docs/technical/two_factor_authentication.md`

---

### Task 1: Add devise-two-factor gem and run bundle

**Files:**
- Modify: `Gemfile`
- Run: `bundle install`

- [ ] **Step 1: Add gem to Gemfile**

Insert after the `devise-api` line (line 59):

```ruby
gem 'devise-two-factor', '~> 5.0'
gem 'rqrcode', '~> 2.0'    # For QR code generation in views
```

- [ ] **Step 2: Install the gem**

Run: `bundle install`
Expected: Both gems installed successfully.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add devise-two-factor and rqrcode gems"
```

---

### Task 2: Migration for 2FA columns on users

**Files:**
- Create: `db/migrate/XXXXXXXXXXXXXX_add_two_factor_to_users.rb`
- Modify: `db/schema.rb` (after running migration)

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration AddTwoFactorToUsers`

- [ ] **Step 2: Write migration content**

```ruby
# db/migrate/XXXXXXXXXXXXXX_add_two_factor_to_users.rb
class AddTwoFactorToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :two_factor_enabled, :boolean, default: false, null: false
    add_column :users, :otp_secret, :text
    add_column :users, :consumed_timestep, :integer
    add_column :users, :otp_backup_codes, :text
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `add_two_factor_to_users` migration runs successfully.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "feat: add 2FA columns to users table"
```

---

### Task 3: User model concern for 2FA

**Files:**
- Create: `app/packs/core/users/models/concerns/two_factor_authenticatable.rb`
- Modify: `app/packs/core/users/models/user.rb`
- Test: `spec/models/user_spec.rb` (or create if needed)

- [ ] **Step 1: Create the concern**

```ruby
# app/packs/core/users/models/concerns/two_factor_authenticatable.rb
module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  included do
    devise :two_factor_authenticatable
    encrypts :otp_secret

    # Ensure otp_secret is generated when 2FA is first enabled
    before_save :generate_otp_secret, if: -> { two_factor_enabled_changed? && two_factor_enabled? && otp_secret.blank? }
  end

  def generate_otp_secret
    self.otp_secret = User.generate_otp_secret
  end

  def send_otp_via_whatsapp
    code = otp_code  # current TOTP code from devise-two-factor
    SendOtpToWhatsappJob.perform_later(id, code)
  end

  def generate_backup_codes!
    codes = 8.times.map { SecureRandom.hex(4).upcase.insert(4, '-') }
    hashed = codes.map { |c| BCrypt::Password.create(c) }
    update!(otp_backup_codes: hashed.to_json)
    codes  # return plaintext for one-time display
  end

  def consume_backup_code!(code)
    codes = JSON.parse(otp_backup_codes || '[]')
    remaining = codes.reject do |hashed|
      BCrypt::Password.new(hashed) == code
    end
    update!(otp_backup_codes: remaining.to_json)
    remaining.size != codes.size  # true if consumed
  end

  def backup_codes_remaining
    codes = JSON.parse(otp_backup_codes || '[]')
    codes.size
  end

  # Override devise-two-factor's method to also check our flag
  def need_two_factor_authentication?(_request)
    two_factor_enabled?
  end
end
```

- [ ] **Step 2: Include concern in User model**

Add after the existing `include` lines (around line 9):

```ruby
include TwoFactorAuthenticatable
```

Also add `:two_factor_authenticatable` to the devise call (line 112-113):

```ruby
devise :database_authenticatable, :registerable, :trackable,
       :recoverable, :rememberable, :validatable, :lockable, :api,
       :two_factor_authenticatable
```

- [ ] **Step 3: Add `two_factor_enabled` to permitted params in UsersController**

In `user_params` method (line 260), add `:two_factor_enabled` to the permitted list for company_admin:

```ruby
params.require(:user).permit(:first_name, :last_name, :email,
                             :phone, :whatsapp_enabled, :two_factor_enabled, :signature, :call_code,
                             :dept, :sale_notification, :enable_support, :tag_list, :entity_id,
                             role_name: [], permissions: [], extended_permissions: [], properties: {}, preferences: {})
```

- [ ] **Step 4: Add `two_factor_enabled` to ransackable_attributes**

In `User.ransackable_attributes` (line 355-356), add `two_factor_enabled`:

```ruby
%w[first_name last_name email phone whatsapp_enabled two_factor_enabled advisor_entity_id].sort
```

- [ ] **Step 5: Add factory trait for 2FA user**

In `test/factories.rb`, add a trait to the `:user` factory (after line 800):

```ruby
trait :with_two_factor do
  two_factor_enabled { true }
  otp_secret { User.generate_otp_secret }
end
```

- [ ] **Step 6: Verify model loads correctly**

Run: `bin/rails runner 'puts User.new.respond_to?(:otp_code)'`
Expected: `true`

- [ ] **Step 7: Commit**

```bash
git add app/packs/core/users/models/concerns/two_factor_authenticatable.rb \
       app/packs/core/users/models/user.rb \
       app/packs/core/users/controllers/users_controller.rb \
       test/factories.rb
git commit -m "feat: add TwoFactorAuthenticatable concern to User model"
```

---

### Task 4: TwoFactorController — Enrollment flow

**Files:**
- Create: `app/packs/core/users/controllers/users/two_factor_controller.rb`
- Create: `app/packs/core/users/views/users/two_factor/enroll.html.erb`
- Create: `app/packs/core/users/views/users/two_factor/backup_codes.html.erb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add routes**

In `config/routes.rb`, inside the `resources :users` block (after line 78), add:

```ruby
resource :two_factor, only: [:new, :create], controller: 'users/two_factor' do
  get  :enroll
  post :verify_enrollment
  post :send_whatsapp
  get  :backup_codes
end
```

- [ ] **Step 2: Create TwoFactorController**

```ruby
# app/packs/core/users/controllers/users/two_factor_controller.rb
module Users
  class TwoFactorController < ApplicationController
    # No authenticate_user! — user is in pre-2FA state
    before_action :require_otp_session
    skip_before_action :verify_authenticity_token, only: [:send_whatsapp]

    def new
      @user = User.find(session[:otp_user_id])
    end

    def create
      @user = User.find(session[:otp_user_id])

      if @user.validate_and_consume_otp!(params[:otp_code])
        complete_login
      elsif @user.otp_backup_codes.present? && consume_backup_code(params[:otp_code])
        complete_login
      else
        increment_failed_attempts
        if session[:otp_failed_attempts] >= 3
          reset_otp_session
          redirect_to new_session_path(User), alert: "Too many failed attempts. Please sign in again."
        else
          flash.now[:alert] = "Invalid code. #{3 - session[:otp_failed_attempts]} attempt(s) remaining."
          render :new
        end
      end
    end

    def enroll
      @user = User.find(session[:otp_user_id])
      @user.generate_otp_secret if @user.otp_secret.blank?
      @user.save! if @user.otp_secret_changed?

      @provisioning_uri = @user.provisioning_uri("IRM:#{@user.email}",
                                                  issuer: "IRM")
      @qr_code = RQRCode::QRCode.new(@provisioning_uri)
    end

    def verify_enrollment
      @user = User.find(session[:otp_user_id])

      if @user.validate_and_consume_otp!(params[:otp_code])
        @user.update!(two_factor_enabled: true)
        @backup_codes = @user.generate_backup_codes!
        sign_in(@user)
        reset_otp_session
        redirect_to backup_codes_user_two_factor_path, notice: "Two-factor authentication is now enabled."
      else
        flash.now[:alert] = "Invalid code. Please try again."
        @provisioning_uri = @user.provisioning_uri("IRM:#{@user.email}",
                                                    issuer: "IRM")
        @qr_code = RQRCode::QRCode.new(@provisioning_uri)
        render :enroll
      end
    end

    def send_whatsapp
      @user = User.find(session[:otp_user_id])

      if session[:otp_whatsapp_sent_at] && Time.current - Time.parse(session[:otp_whatsapp_sent_at]) < 30
        render json: { error: "Please wait 30 seconds before requesting another code." }, status: :too_many_requests
        return
      end

      @user.send_otp_via_whatsapp
      session[:otp_whatsapp_sent_at] = Time.current.to_s
      render json: { message: "Code sent! Check your WhatsApp messages." }
    end

    def backup_codes
      @backup_codes = session[:otp_backup_codes] || []
      # Clear from session after display
      session.delete(:otp_backup_codes)
    end

    private

    def require_otp_session
      unless session[:otp_user_id].present?
        redirect_to new_session_path(User), alert: "Session expired. Please sign in again."
      end
    end

    def complete_login
      sign_in(@user)
      reset_otp_session
      redirect_to after_sign_in_path_for(@user), notice: "Signed in successfully."
    end

    def consume_backup_code(code)
      if @user.consume_backup_code!(code)
        true
      else
        false
      end
    end

    def increment_failed_attempts
      session[:otp_failed_attempts] ||= 0
      session[:otp_failed_attempts] += 1
    end

    def reset_otp_session
      session.delete(:otp_user_id)
      session.delete(:otp_failed_attempts)
      session.delete(:otp_whatsapp_sent_at)
    end
  end
end
```

- [ ] **Step 3: Create enrollment view**

```erb
<%# app/packs/core/users/views/users/two_factor/enroll.html.erb %>
<div class="login-container">
  <div class="login-header">
    <h2 class="h3 mb-2 fw-normal">Set Up Two-Factor Authentication</h2>
    <p class="text-muted">Scan this QR code with your authenticator app</p>
  </div>

  <div class="login-body text-center">
    <%- flash.each do |name, msg| -%>
      <%= content_tag :div, msg, id: "flash_#{name}", class: "alert alert-info text-center" if msg.is_a?(String) %>
    <%- end -%>

    <div class="mb-4">
      <p class="text-muted mb-3">
        1. Install Google Authenticator, Authy, or any TOTP authenticator app.
      </p>
      <p class="text-muted mb-3">
        2. Scan this QR code:
      </p>

      <div class="d-inline-block p-3 bg-white rounded border mb-3">
        <%= raw @qr_code.as_svg(
          module_size: 4,
          standalone: true,
          use_path: true
        ) %>
      </div>

      <p class="text-muted mb-3">
        Or enter this key manually: <code><%= @user.otp_secret.scan(/.{4}/).join(' ') %></code>
      </p>
    </div>

    <p class="text-muted mb-3">
      3. Enter the 6-digit code from your app to confirm:
    </p>

    <%= form_tag verify_enrollment_user_two_factor_path, data: { turbo: false } do %>
      <div class="form-group mb-3">
        <%= text_field_tag :otp_code, nil,
              class: "form-control-modern text-center",
              placeholder: "000000",
              maxlength: 6,
              pattern: "[0-9]{6}",
              inputmode: "numeric",
              autocomplete: "one-time-code",
              required: true %>
      </div>

      <%= submit_tag "Confirm & Enable 2FA",
            class: "glow-edge btn btn-primary w-100",
            data: { disable_with: "Verifying..." } %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Create backup codes view**

```erb
<%# app/packs/core/users/views/users/two_factor/backup_codes.html.erb %>
<div class="login-container">
  <div class="login-header">
    <h2 class="h3 mb-2 fw-normal">Backup Codes</h2>
    <p class="text-muted">Save these codes in a safe place. Each code can be used only once.</p>
  </div>

  <div class="login-body">
    <div class="alert alert-warning">
      <strong>Important:</strong> If you lose your authenticator app, these backup codes are the only way to access your account.
    </div>

    <div class="p-3 bg-light rounded mb-3">
      <% @backup_codes.each do |code| %>
        <div class="text-center py-1 font-monospace" style="font-size: 1.2rem; letter-spacing: 2px;">
          <%= code %>
        </div>
      <% end %>
    </div>

    <%= link_to "Continue to Dashboard", root_path, class: "glow-edge btn btn-primary w-100" %>
  </div>
</div>
```

- [ ] **Step 5: Commit**

```bash
git add app/packs/core/users/controllers/users/two_factor_controller.rb \
       app/packs/core/users/views/users/two_factor/ \
       config/routes.rb
git commit -m "feat: add TwoFactorController with enrollment flow"
```

---

### Task 5: Modify SessionsController for 2FA intercept

**Files:**
- Modify: `app/packs/core/users/controllers/users/sessions_controller.rb`

- [ ] **Step 1: Update SessionsController to intercept for 2FA**

```ruby
# app/packs/core/users/controllers/users/sessions_controller.rb
module Users
  class SessionsController < Devise::SessionsController
    def create
      self.resource = warden.authenticate!(auth_options)

      if resource.two_factor_enabled?
        if resource.otp_secret.blank?
          # First-time 2FA setup — generate secret and redirect to enrollment
          session[:otp_user_id] = resource.id
          sign_out(resource)
          redirect_to enroll_user_two_factor_path
        else
          # 2FA required — store user in session, don't sign in yet
          session[:otp_user_id] = resource.id
          sign_out(resource)
          redirect_to new_user_two_factor_path
        end
      else
        # Standard login (no 2FA)
        sign_in(resource)
        resource.update(session_token: SecureRandom.hex(64))
        cookies[:session_token] = { value: resource.session_token, httponly: true, secure: !Rails.env.local? }
        redirect_to after_sign_in_path_for(resource)
      end
    rescue ActiveRecord::RecordNotUnique => e
      # Handle race condition on session_token update
      retry
    end

    def destroy
      reset_session
      super
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/packs/core/users/controllers/users/sessions_controller.rb
git commit -m "feat: add 2FA intercept to SessionsController"
```

---

### Task 6: Modify magic link login for 2FA intercept

**Files:**
- Modify: `app/packs/core/users/controllers/users_controller.rb`

- [ ] **Step 1: Update no_password_login for 2FA**

In `no_password_login` action (line 114), after the user is found and verified, add the 2FA check before `sign_in`:

```ruby
def no_password_login
  # ... existing support_user setup code (lines 118-150) ...

  ActiveRecord::Base.connected_to(role: :writing) do
    if @user.two_factor_enabled?
      if @user.otp_secret.blank?
        session[:otp_user_id] = @user.id
        redirect_to enroll_user_two_factor_path
        return
      else
        session[:otp_user_id] = @user.id
        redirect_to new_user_two_factor_path
        return
      end
    end

    sign_in @user
    # Set support_user_id in session so the audit trail records who actually made changes.
    session[:support_user_id] = support_user_id if support_user_id.present?
  end

  redirect_to(params[:redirect_to].presence || session[:user_return_to].presence || root_path,
              notice: "Signed in successfully")
end
```

- [ ] **Step 2: Commit**

```bash
git add app/packs/core/users/controllers/users_controller.rb
git commit -m "feat: add 2FA intercept to magic link login"
```

---

### Task 7: 2FA code entry view

**Files:**
- Create: `app/packs/core/users/views/users/two_factor/new.html.erb`

- [ ] **Step 1: Create the code entry view**

```erb
<%# app/packs/core/users/views/users/two_factor/new.html.erb %>
<div id="two_factor_page" data-controller="two-factor">
  <div class="login-container">
    <div class="login-header">
      <h2 class="h3 mb-2 fw-normal">Two-Factor Authentication</h2>
      <p class="text-muted">Enter the 6-digit code from your authenticator app</p>
    </div>

    <div class="login-body">
      <%- flash.each do |name, msg| -%>
        <%= content_tag :div, msg, id: "flash_#{name}", class: "alert alert-info text-center" if msg.is_a?(String) %>
      <%- end -%>

      <%= form_tag user_two_factor_path, data: { turbo: false } do %>
        <div class="form-group mb-3">
          <%= text_field_tag :otp_code, nil,
                class: "form-control-modern text-center",
                placeholder: "000000",
                maxlength: 6,
                pattern: "[0-9]{6}",
                inputmode: "numeric",
                autocomplete: "one-time-code",
                required: true,
                autofocus: true %>
        </div>

        <%= submit_tag "Verify",
              class: "glow-edge btn btn-primary w-100",
              data: { disable_with: "Verifying..." } %>
      <% end %>

      <div class="divider"><span>OR</span></div>

      <button type="button" id="send-whatsapp-btn" class="btn btn-secondary w-100" data-action="click->two-factor#sendWhatsapp">
        <i class="fab fa-whatsapp"></i> Send code via WhatsApp
      </button>

      <div id="whatsapp-status" class="text-center mt-2" style="display: none;"></div>

      <div class="text-center mt-3">
        <small class="text-muted">
          Having trouble? Contact your administrator.
        </small>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Create Stimulus controller for WhatsApp send**

```javascript
// app/javascript/controllers/two_factor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
  }

  sendWhatsapp(event) {
    event.preventDefault()
    const btn = event.currentTarget
    const status = document.getElementById("whatsapp-status")

    btn.disabled = true
    status.style.display = "block"
    status.textContent = "Sending code..."
    status.className = "text-center mt-2 text-info"

    fetch("/users/two_factor/send_whatsapp", {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Content-Type": "application/json"
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.error) {
        status.textContent = data.error
        status.className = "text-center mt-2 text-danger"
      } else {
        status.textContent = data.message
        status.className = "text-center mt-2 text-success"
      }
    })
    .catch(() => {
      status.textContent = "Failed to send code. Please try again."
      status.className = "text-center mt-2 text-danger"
    })
    .finally(() => {
      btn.disabled = false
    })
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/packs/core/users/views/users/two_factor/new.html.erb \
       app/javascript/controllers/two_factor_controller.js
git commit -m "feat: add 2FA code entry view and Stimulus controller"
```

---

### Task 8: WhatsApp OTP delivery job

**Files:**
- Create: `app/packs/core/users/jobs/send_otp_whatsapp_job.rb`

- [ ] **Step 1: Create the job**

```ruby
# app/packs/core/users/jobs/send_otp_whatsapp_job.rb
class SendOtpToWhatsappJob < ApplicationJob
  queue_as :default

  def perform(user_id, code)
    user = User.find(user_id)
    return unless user.phone.present?

    message = "Your IRM verification code is: #{code}. It expires in 30 seconds."

    begin
      WhatsappGeneralNotification.send_session_message(
        whatsapp_number: user.phone_with_call_code,
        message: message
      )
    rescue StandardError => e
      Rails.logger.warn "WhatsApp session message failed for user #{user_id}: #{e.message}"
      # Fall back to template message
      entity = user.entity
      if entity&.entity_setting&.fetch_whatsapp_endpoint.present?
        WhatsappGeneralNotification.send_message(
          endpoint: entity.entity_setting.fetch_whatsapp_endpoint,
          token: entity.entity_setting.fetch_whatsapp_token,
          template_name: entity.entity_setting.fetch_whatsapp_template(:otp_verification),
          whatsapp_number: user.phone_with_call_code,
          entity_name: entity.name,
          message: "Your verification code is: #{code}",
          link: ""
        )
      end
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/packs/core/users/jobs/send_otp_whatsapp_job.rb
git commit -m "feat: add SendOtpToWhatsappJob for WhatsApp OTP delivery"
```

---

### Task 9: Cucumber tests for 2FA enrollment

**Files:**
- Create: `features/login/two_factor_enrollment.feature`
- Create: `features/step_definitions/two_factor_steps.rb`

- [ ] **Step 1: Create the enrollment feature file**

```gherkin
# features/login/two_factor_enrollment.feature
Feature: Two-Factor Authentication Enrollment
  Users with 2FA enabled need to set up their authenticator app before first use.

  Scenario Outline: User enrolls in 2FA for the first time
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA enrollment page
    And I should see a QR code for setup
    When I enter a valid TOTP code and confirm
    Then I should see backup codes
    And the user should have 2FA enabled

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters invalid code during enrollment
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled but not configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA enrollment page
    When I enter an invalid TOTP code and confirm
    Then I should see "Invalid code"
    And I should still be on the enrollment page

    Examples:
      | user | entity              |
      |      | entity_type=Company |
```

- [ ] **Step 2: Create step definitions for 2FA**

```ruby
# features/step_definitions/two_factor_steps.rb
Given("the user has two-factor authentication enabled but not configured") do
  @user.update!(two_factor_enabled: true)
  # otp_secret is nil — will be generated on enrollment page
end

Given("the user has two-factor authentication enabled and configured") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret)
end

Then("I should be on the 2FA enrollment page") do
  expect(page).to have_current_path(enroll_user_two_factor_path, wait: 10)
  expect(page).to have_content("Set Up Two-Factor Authentication")
end

Then("I should see a QR code for setup") do
  expect(page).to have_css("svg", wait: 5) # QR code rendered as SVG
end

When("I enter a valid TOTP code and confirm") do
  # Generate a valid TOTP code using the user's secret
  @user.reload
  code = @user.otp_code
  fill_in("otp_code", with: code)
  click_on("Confirm & Enable 2FA")
end

When("I enter an invalid TOTP code and confirm") do
  fill_in("otp_code", with: "000000")
  click_on("Confirm & Enable 2FA")
end

Then("I should see backup codes") do
  expect(page).to have_content("Backup Codes")
  expect(page).to have_content("Continue to Dashboard")
end

Then("the user should have 2FA enabled") do
  @user.reload
  expect(@user.two_factor_enabled).to be true
  expect(@user.otp_secret).not_to be_nil
  expect(@user.otp_backup_codes).not_to be_nil
end

Then("I should still be on the enrollment page") do
  expect(page).to have_current_path(verify_enrollment_user_two_factor_path, wait: 5)
end
```

- [ ] **Step 3: Run the enrollment tests**

Run: `bundle exec cucumber features/login/two_factor_enrollment.feature`
Expected: All scenarios pass.

- [ ] **Step 4: Commit**

```bash
git add features/login/two_factor_enrollment.feature \
       features/step_definitions/two_factor_steps.rb
git commit -m "test: add Cucumber tests for 2FA enrollment"
```

---

### Task 10: Cucumber tests for 2FA verification (password login)

**Files:**
- Create: `features/login/two_factor_verification.feature`
- Modify: `features/step_definitions/two_factor_steps.rb`

- [ ] **Step 1: Create the verification feature file**

```gherkin
# features/login/two_factor_verification.feature
Feature: Two-Factor Authentication Verification
  Users with 2FA enabled must enter a TOTP code after password authentication.

  Scenario Outline: User logs in with password and completes 2FA
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters invalid TOTP code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code
    Then I should see "Invalid code"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters wrong TOTP code 3 times
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid TOTP code 3 times
    Then I should be redirected to the login page
    And I should see "Too many failed attempts"

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User without 2FA logs in normally
    Given there is a user "<user>" for an entity "<entity>"
    And I am at the login page
    When I fill and submit the login page
    Then I should see "Signed in successfully"
    And I should not be on the 2FA verification page

    Examples:
      | user | entity              |
      |      | entity_type=Company |
```

- [ ] **Step 2: Add step definitions**

Append to `features/step_definitions/two_factor_steps.rb`:

```ruby
Then("I should be on the 2FA verification page") do
  expect(page).to have_current_path(new_user_two_factor_path, wait: 10)
  expect(page).to have_content("Two-Factor Authentication")
end

When("I enter a valid TOTP code") do
  @user.reload
  code = @user.otp_code
  fill_in("otp_code", with: code)
  click_on("Verify")
end

When("I enter an invalid TOTP code") do
  fill_in("otp_code", with: "000000")
  click_on("Verify")
end

When("I enter an invalid TOTP code {int} times") do |count|
  count.times do
    fill_in("otp_code", with: "000000")
    click_on("Verify")
    # Wait for page to reload between attempts
    sleep(0.5) unless count == 1
  end
end

Then("I should be redirected to the login page") do
  expect(page).to have_current_path(new_session_path(User), wait: 10)
end

Then("I should not be on the 2FA verification page") do
  expect(page).not_to have_content("Two-Factor Authentication")
end
```

- [ ] **Step 3: Run the verification tests**

Run: `bundle exec cucumber features/login/two_factor_verification.feature`
Expected: All scenarios pass.

- [ ] **Step 4: Commit**

```bash
git add features/login/two_factor_verification.feature \
       features/step_definitions/two_factor_steps.rb
git commit -m "test: add Cucumber tests for 2FA verification with password login"
```

---

### Task 11: Cucumber tests for 2FA with magic link

**Files:**
- Create: `features/login/two_factor_magic_link.feature`
- Modify: `features/step_definitions/two_factor_steps.rb`

- [ ] **Step 1: Create the magic link + 2FA feature file**

```gherkin
# features/login/two_factor_magic_link.feature
Feature: Two-Factor Authentication with Magic Link
  Users with 2FA enabled must complete 2FA after clicking a magic link.

  Scenario Outline: User logs in via magic link and completes 2FA
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured
    And I am at the login page without password
    When I fill and submit the login without password
    Then I should see the "<msg>"
    And the user receives an email with "<subject>" in the subject
    And when I click on the link in the email "<link>"
    Then I should be on the 2FA verification page
    When I enter a valid TOTP code
    Then I should see "Signed in successfully"

    Examples:
      |user | msg                                                                    | subject                          | link          |
      |     |If that address is registered, a login link is on its way.               | Login Link: Expires in 10 minutes | Click To Login|

  Scenario Outline: User without 2FA logs in via magic link normally
    Given there is a user "<user>" for an entity "<entity>"
    And I am at the login page without password
    When I fill and submit the login without password
    Then I should see the "<msg>"
    And the user receives an email with "<subject>" in the subject
    And when I click on the link in the email "<link>"
    Then I should see the "<login_msg>"
    And I should not be on the 2FA verification page

    Examples:
      |user | login_msg               | subject                          | link          | msg |
      |     |Signed in successfully   | Login Link: Expires in 10 minutes | Click To Login|If that address is registered, a login link is on its way.|
```

- [ ] **Step 2: Run the magic link tests**

Run: `bundle exec cucumber features/login/two_factor_magic_link.feature`
Expected: All scenarios pass.

- [ ] **Step 3: Commit**

```bash
git add features/login/two_factor_magic_link.feature
git commit -m "test: add Cucumber tests for 2FA with magic link"
```

---

### Task 12: Cucumber tests for backup codes

**Files:**
- Create: `features/login/two_factor_backup_codes.feature`
- Modify: `features/step_definitions/two_factor_steps.rb`

- [ ] **Step 1: Create the backup codes feature file**

```gherkin
# features/login/two_factor_backup_codes.feature
Feature: Two-Factor Authentication Backup Codes
  Users can use backup codes if they don't have access to their authenticator app.

  Scenario Outline: User logs in using a backup code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured with backup codes
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter a valid backup code
    Then I should see "Signed in successfully"
    And the backup code should be consumed

    Examples:
      | user | entity              |
      |      | entity_type=Company |

  Scenario Outline: User enters an invalid backup code
    Given there is a user "<user>" for an entity "<entity>"
    And the user has two-factor authentication enabled and configured with backup codes
    And I am at the login page
    When I fill and submit the login page
    Then I should be on the 2FA verification page
    When I enter an invalid backup code
    Then I should see "Invalid code"

    Examples:
      | user | entity              |
      |      | entity_type=Company |
```

- [ ] **Step 2: Add step definitions**

Append to `features/step_definitions/two_factor_steps.rb`:

```ruby
Given("the user has two-factor authentication enabled and configured with backup codes") do
  secret = User.generate_otp_secret
  @user.update!(two_factor_enabled: true, otp_secret: secret)
  @backup_codes = @user.generate_backup_codes!
end

When("I enter a valid backup code") do
  fill_in("otp_code", with: @backup_codes.first)
  click_on("Verify")
end

When("I enter an invalid backup code") do
  fill_in("otp_code", with: "INVALID-CODE")
  click_on("Verify")
end

Then("the backup code should be consumed") do
  @user.reload
  remaining = JSON.parse(@user.otp_backup_codes || '[]')
  expect(remaining.size).to eq(7) # 8 original - 1 consumed
end
```

- [ ] **Step 3: Run the backup codes tests**

Run: `bundle exec cucumber features/login/two_factor_backup_codes.feature`
Expected: All scenarios pass.

- [ ] **Step 4: Commit**

```bash
git add features/login/two_factor_backup_codes.feature \
       features/step_definitions/two_factor_steps.rb
git commit -m "test: add Cucumber tests for 2FA backup codes"
```

---

### Task 13: Run full test suite and verify no regressions

**Files:**
- Run: existing test suite

- [ ] **Step 1: Run existing Cucumber login tests**

Run: `bundle exec cucumber features/login/login.feature`
Expected: All existing login scenarios pass (no regression).

- [ ] **Step 2: Run all 2FA Cucumber tests**

Run: `bundle exec cucumber features/login/two_factor_*.feature`
Expected: All 2FA scenarios pass.

- [ ] **Step 3: Run RSpec tests**

Run: `bundle exec rspec` (or relevant spec files)
Expected: All existing tests pass.

- [ ] **Step 4: Run RuboCop**

Run: `bundle exec rubocop -a`
Expected: No offenses.

- [ ] **Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "chore: fix linting and finalize 2FA implementation"
```
