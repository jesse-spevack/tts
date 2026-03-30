# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class OpenapiControllerTest < ActionDispatch::IntegrationTest
      test "returns OpenAPI 3.1 spec as JSON" do
        get api_v1_openapi_path

        assert_response :success
        spec = response.parsed_body
        assert_equal "3.1.0", spec["openapi"]
        assert_equal "PodRead API", spec["info"]["title"]
      end

      test "does not require authentication" do
        get api_v1_openapi_path
        assert_response :success
      end

      test "includes all 7 operations" do
        get api_v1_openapi_path
        spec = response.parsed_body

        # Verify all operation IDs are present
        operation_ids = extract_operation_ids(spec["paths"])
        expected = %w[createEpisode listEpisodes getEpisode deleteEpisode listVoices getFeed getAuthStatus]
        assert_equal expected.sort, operation_ids.sort
      end

      test "createEpisode only exposes url and text source types" do
        get api_v1_openapi_path
        spec = response.parsed_body

        create_schema = spec.dig("paths", "/api/v1/episodes", "post", "requestBody", "content", "application/json", "schema")
        source_type_enum = create_schema.dig("properties", "source_type", "enum")
        assert_equal [ "url", "text" ], source_type_enum
        assert_not_includes source_type_enum, "extension"
      end

      test "includes component schemas" do
        get api_v1_openapi_path
        spec = response.parsed_body

        schemas = spec.dig("components", "schemas")
        assert schemas.key?("Episode")
        assert schemas.key?("Voice")
        assert schemas.key?("PaginationMeta")
      end

      test "episode schema matches actual API response shape" do
        get api_v1_openapi_path
        spec = response.parsed_body

        episode_props = spec.dig("components", "schemas", "Episode", "properties")
        expected_fields = %w[id title author description status source_type source_url duration_seconds error_message created_at]
        assert_equal expected_fields.sort, episode_props.keys.sort
      end

      test "includes server URL" do
        get api_v1_openapi_path
        spec = response.parsed_body

        servers = spec["servers"]
        assert_equal 1, servers.length
        assert servers.first["url"].present?
      end

      test "descriptions fit ChatGPT character limits" do
        get api_v1_openapi_path
        spec = response.parsed_body

        spec["paths"].each do |path, methods|
          methods.each do |method, operation|
            next unless operation.is_a?(Hash) && operation["description"]

            desc = operation["description"]
            assert desc.length <= 300,
              "#{method.upcase} #{path} description is #{desc.length} chars (max 300): #{desc[0..50]}..."

            (operation["parameters"] || []).each do |param|
              if param["description"]
                assert param["description"].length <= 700,
                  "#{method.upcase} #{path} param '#{param["name"]}' description is #{param["description"].length} chars (max 700)"
              end
            end
          end
        end
      end

      private

      def extract_operation_ids(paths)
        paths.flat_map do |_path, methods|
          methods.filter_map { |_method, operation| operation["operationId"] if operation.is_a?(Hash) }
        end
      end
    end
  end
end
