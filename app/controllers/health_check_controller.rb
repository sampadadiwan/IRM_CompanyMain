class HealthCheckController < ApplicationController
  skip_after_action :verify_authorized, only: %i[redis_check db_check elastic_check]

  def redis_check
    now = Time.zone.now.to_s
    Rails.cache.write('now', now)

    respond_to do |format|
      if now == Rails.cache.read('now')
        format.json { render json: "Ok", status: :ok }
      else
        raise "Cache not reachable"
      end
    end
  end

  def db_check
    respond_to do |format|
      if User.first
        format.json { render json: "Ok", status: :ok }
      else
        raise "DB not reachable"
      end
    end
  end

  def elastic_check
    respond_to do |format|
      if Folder.search("Test", 1)
        format.json { render json: "Ok", status: :ok }
      else
        raise "DB not reachable"
      end
    end
  end
end
