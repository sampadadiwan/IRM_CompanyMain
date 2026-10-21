module Users
  # Changing a user's EXISTING mobile number. The "Change phone" modal on users/show posts the
  # new number to #create, which emails a code to the user; #show asks for that code and
  # #update checks it. The rules live in PhoneChangeStart / PhoneChangeConfirm and, finally,
  # User#existing_phone_change_must_be_verified.
  class PhoneChangesController < ApplicationController
    before_action :set_user

    # GET /users/:user_id/phone_change — the "enter the code" page.
    def show
      # Only meaningful while a code is waiting; otherwise send them back to the user page.
      @request = @user.phone_change_requests.pending.order(created_at: :desc).first
      return if @request && !@request.expired?

      redirect_to user_path(@user), alert: "There is no phone change waiting for a code."
    end

    # POST /users/:user_id/phone_change — check the new number and email the code.
    def create
      result = PhoneChangeStart.call(user: @user, actor: current_user,
                                     call_code: params[:call_code], phone: params[:phone])

      if result.success?
        redirect_to user_phone_change_path(@user), notice: "A 6-digit code has been emailed to #{@user.email}."
      else
        redirect_to user_path(@user), alert: result[:errors]
      end
    end

    # PATCH /users/:user_id/phone_change — check the code and save the new number.
    def update
      result = PhoneChangeConfirm.call(user: @user, actor: current_user, code: params[:code])

      if result.success?
        redirect_to user_path(@user), notice: "Mobile number changed to #{@user.reload.masked_phone_with_call_code}."
      elsif result[:request_open]
        # Wrong code with guesses left: ask again on the same page.
        redirect_to user_phone_change_path(@user), alert: result[:errors]
      else
        redirect_to user_path(@user), alert: result[:errors]
      end
    end

    private

    # Every action is authorized against the target user here, so none can run unchecked.
    def set_user
      @user = User.find(params[:user_id])
      authorize @user, :change_phone?
    end
  end
end
