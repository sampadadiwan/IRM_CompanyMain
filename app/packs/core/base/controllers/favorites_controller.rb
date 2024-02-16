class FavoritesController < ApplicationController
  before_action :set_favorite, only: %i[show edit update destroy]

  def index
    @favorites = policy_scope(Favorite)
  end

  def create
    @favorite = Favorite.new
    @favorite.favoritable_type = params[:favoritable_type]
    @favorite.favoritable_id = params[:favoritable_id]
    @favorite.favoritor = current_user
    authorize @favorite

    msg = @favorite.save ? "Favorited!" : "Already in favorites."

    redirect_to @favorite.favoritable, alert: msg
  end

  def destroy
    @favorite.destroy
    redirect_to @favorite.favoritable
  end

  private

  def set_favorite
    @favorite = Favorite.find(params[:id])
    authorize @favorite
  end

  def favorite_params
    params.require(:favorite).permit(:favoriteable_id, :favoriteable_type)
  end
end
