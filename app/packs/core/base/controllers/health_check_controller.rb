class HealthCheckController < ApplicationController
  before_action :authenticate_user!, except: %i[redis_check db_check elastic_check xirr_check replication_check disk_check cross_site_trust]
  skip_after_action :verify_authorized, only: %i[redis_check db_check elastic_check xirr_check replication_check disk_check cross_site_trust]

  # Publishes a non-reversible fingerprint of this region's inter-region shared secret so the
  # peer region (and an operator with curl) can confirm the two still match, without either
  # side disclosing the secret. Unauthenticated like the other health checks - the response
  # carries no secret material.
  #
  # Always 200, including when the secret is missing: this is a configuration report, not a
  # liveness probe, and a non-200 here would take the box out of the load balancer.
  def cross_site_trust
    render json: {
      region: SiteRegistry.current_code,
      configured: CrossSiteTrust.configured?,
      fingerprint: CrossSiteTrust.fingerprint
    }, status: :ok
  end

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

  def disk_check
    # Execute the `df -h` command to get disk space usage
    disk_usage = `df -h`

    # Find the line that contains the root filesystem (assuming it's mounted on /)
    root_fs_line = disk_usage.split("\n").find { |line| line.include?(' /') }

    if root_fs_line
      # Extract the percentage usage from the line
      usage_percentage = root_fs_line.split[4].to_i

      # Check if the usage is 95% or more
      if usage_percentage >= 95
        Rails.logger.debug { "Warning: Disk space is at #{usage_percentage}%" }
      else
        Rails.logger.debug { "Disk space is at #{usage_percentage}%. All good!" }
      end
    else
      Rails.logger.debug "Could not find root filesystem information."
    end

    respond_to do |format|
      if usage_percentage < 95
        format.json { render json: "Ok", status: :ok }
      else
        raise "Disk space is at #{usage_percentage}%."
      end
    end
  end

  def replication_check
    respond_to do |format|
      status = ReplicationHealthJob.new.replication_health_status
      if status == "Ok"
        format.json { render json: "Ok", status: :ok }
      else
        raise status
      end
    end
  end

  def elastic_check
    respond_to do |format|
      if Folder.search("Test", 1)
        format.json { render json: "Ok", status: :ok }
      else
        raise "ES not reachable"
      end
    end
  end

  def xirr_check
    begin
      response = XirrApi.new.check
    rescue StandardError => e
      response = nil
    end

    respond_to do |format|
      if response && response.code == 200
        format.json { render json: "Ok", status: :ok }
      else
        raise "XIRR not reachable #{e&.message}"
      end
    end
  end
end
