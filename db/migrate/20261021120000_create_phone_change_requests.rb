# One attempt to change a user's EXISTING mobile number, confirmed by a code emailed to the
# user (User#existing_phone_change_must_be_verified, PhoneChangeStart, PhoneChangeConfirm).
#
# Why a table rather than columns on users: the change is additive (nothing on users moves),
# and every attempt — who asked, which number, whether it was confirmed — stays on record for
# support and for spotting someone repeatedly trying to re-point an account's phone.
class CreatePhoneChangeRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :phone_change_requests do |t|
      # The user whose number changes; the code goes to THEIR email.
      t.references :user, null: false, foreign_key: true
      # Who started it — the user themselves or a company admin / support user.
      t.references :requested_by, null: false, foreign_key: { to_table: :users }

      # The number being changed TO. Same shape as users.call_code / users.phone.
      t.string :new_call_code, limit: 3, null: false
      t.string :new_phone, limit: 100, null: false

      # HMAC of the 6-digit code, never the code itself. Null until SendPhoneChangeCodeJob
      # has generated and emailed the code.
      t.string :code_digest, limit: 64
      t.datetime :expires_at, null: false
      # Wrong guesses so far; the request dies at PhoneChangeRequest::MAX_ATTEMPTS.
      t.integer :attempts, null: false, default: 0

      # Exactly one of these ends a request: confirmed, or superseded / locked out.
      t.datetime :verified_at
      t.datetime :cancelled_at

      t.timestamps
    end

    # The rate-limit query ("how many requests for this user in the last hour?") and the
    # pending-request lookup both start from the user and the newest rows.
    add_index :phone_change_requests, %i[user_id created_at]
  end
end
