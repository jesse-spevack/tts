# frozen_string_literal: true

module Simulation
  module CloudStorage
    include StructuredLogging

    def initialize(bucket_name = nil, podcast_id:)
      @bucket_name = bucket_name || AppConfig::Storage::BUCKET
      @podcast_id = podcast_id
      @sim_dir = Rails.root.join("tmp/simulated_uploads")
    end

    def upload_staging_file(content:, filename:)
      path = local_path("staging/#{filename}")
      write_file(path, content)
      log_info "simulation_storage_upload", path: "staging/#{filename}", podcast_id: @podcast_id, bytes: content.bytesize
      "staging/#{filename}"
    end

    def upload_content(content:, remote_path:)
      path = local_path(remote_path)
      write_file(path, content)
      log_info "simulation_storage_upload", path: remote_path, podcast_id: @podcast_id, bytes: content.bytesize
    end

    def download_file(remote_path:)
      path = local_path(remote_path)
      full_path = scoped_path(remote_path)

      unless File.exist?(path)
        raise "File not found: #{full_path}"
      end

      log_info "simulation_storage_download", path: remote_path, podcast_id: @podcast_id
      File.binread(path).force_encoding("UTF-8")
    end

    def delete_file(remote_path:)
      path = local_path(remote_path)

      unless File.exist?(path)
        log_info "simulation_storage_delete_not_found", path: remote_path, podcast_id: @podcast_id
        return false
      end

      File.delete(path)
      log_info "simulation_storage_delete", path: remote_path, podcast_id: @podcast_id
      true
    end

    private

    def scoped_path(path)
      "podcasts/#{@podcast_id}/#{path}"
    end

    def local_path(relative_path)
      @sim_dir.join(scoped_path(relative_path))
    end

    def write_file(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end
  end
end
