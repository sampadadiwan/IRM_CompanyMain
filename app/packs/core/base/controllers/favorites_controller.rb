class FavoritesController < ApplicationController
  before_action :set_favorite, only: %i[show edit update destroy]

  def index
    @favorites = policy_scope(Favorite)
  end

  def create
    @favorite = Favorite.new(favorite_params)
    @favorite.user = current_user
    authorize @favorite

    msg = if @favorite.save
            "Favorited!"
          elsif @favorite.errors[:url].include?("has already been taken")
            "Already in favorites."
          else
            "Failed to add to favorites: #{@favorite.errors.full_messages.join(', ')}"
          end

    respond_to do |format|
      format.html do
        redirect_to request.referer || @favorite.url, notice: msg
      end
      format.turbo_stream do
        render :create, locals: { msg: }
      end
    end
  end

  def destroy
    @favorite.destroy
    redirect_to request.referer || @favorite.url, alert: "Removed from favorites."
  end

  private

  def set_favorite
    @favorite = Favorite.find(params[:id])
    authorize @favorite
  end

  def favorite_params
    params.require(:favorite).permit(:url, :title)
  end
end
