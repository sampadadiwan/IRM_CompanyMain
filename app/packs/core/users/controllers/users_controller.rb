class UsersController < ApplicationController
  # prepend_view_path 'app/packs/core/users/views'

  before_action :authenticate_user!, except: ["welcome"]
  before_action :set_user, only: %w[show update destroy edit]
  after_action :verify_authorized, except: %i[welcome index search reset_password accept_terms set_persona]

  # GET /users or /users.json
  def index
    @users = policy_scope(User)
  end

  def welcome; end

  def search
    query = params[:query]
    if query.present?
      @users = UserIndex.filter(term: { entity_id: current_user.entity_id })
                        .query(query_string: { fields: %i[first_name last_name email],
                                               query:, default_operator: 'and' })

      render "index"
    else
      redirect_to users_path
    end
  end

  # GET /users/1 or /users/1.json
  def show
    authorize @user
  end

  # GET /users/new
  def new
    @user = User.new
    @user.entity_id = params[:entity_id]
    authorize @user
  end

  # GET /users/1/edit
  def edit
    authorize @user
  end

  # PATCH/PUT /users/1 or /users/1.json
  def update
    authorize @user
    respond_to do |format|
      if @user.update(user_params)

        if current_user.has_cached_role?(:company_admin)
          User::UPDATABLE_ROLES.each do |role|
            user_params[:role_name].present? && user_params[:role_name].include?(role) ? @user.add_role(role) : @user.remove_role(role)
          end
        end
        format.html { redirect_to user_url(@user), notice: "User was successfully updated." }
        format.json { render :show, status: :ok, location: @user }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /users/1 or /users/1.json
  def destroy
    authorize @user
    @user.destroy

    respond_to do |format|
      format.html { redirect_to users_url, notice: "User was successfully deleted." }
      format.json { head :no_content }
    end
  end

  def accept_terms
    current_user.accept_terms = true
    current_user.save

    # puts current_user.to_json

    redirect_to root_path
  end

  def set_persona
    current_user.curr_role = params[:persona] if params[:persona].present? &&
                                                 current_user.has_cached_role?(params[:persona].to_sym)
    current_user.save
    redirect_to root_path
  end

  # This is used to reset password only for system generated users on the first login
  def reset_password
    raw, hashed = Devise.token_generator.generate(User, :reset_password_token)
    current_user.reset_password_token = hashed
    current_user.reset_password_sent_at = Time.now.utc
    current_user.save

    sign_out current_user

    redirect_to edit_user_password_path(reset_password_token: raw)
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def user_params
    params.require(:user).permit(:first_name, :last_name, :phone, :whatsapp_enabled, :signature,
                                 :dept, :sale_notification, role_name: [], permissions: [])
  end
end
