# frozen_string_literal: true

module Api
  module V1
    class OpenapiController < ActionController::API
      # No auth required — the spec itself is public.
      # ChatGPT fetches this URL to discover available operations.

      def show
        render json: openapi_spec
      end

      private

      def openapi_spec
        {
          openapi: "3.1.0",
          info: {
            title: "PodRead API",
            description: "Turn articles and text into podcast episodes. PodRead converts web articles or pasted text into natural-sounding audio you can listen to in any podcast app.",
            version: "1.0.0"
          },
          servers: [
            { url: AppConfig::Domain::BASE_URL }
          ],
          paths: {
            "/api/v1/episodes" => {
              post: create_episode_operation,
              get: list_episodes_operation
            },
            "/api/v1/episodes/{id}" => {
              get: get_episode_operation,
              delete: delete_episode_operation
            },
            "/api/v1/voices" => {
              get: list_voices_operation
            },
            "/api/v1/feed" => {
              get: get_feed_operation
            },
            "/api/v1/auth/status" => {
              get: get_auth_status_operation
            }
          },
          components: {
            schemas: schemas,
            securitySchemes: {
              oauth2: {
                type: "oauth2",
                flows: {
                  authorizationCode: {
                    authorizationUrl: "#{AppConfig::Domain::BASE_URL}/oauth/authorize",
                    tokenUrl: "#{AppConfig::Domain::BASE_URL}/oauth/token",
                    scopes: {
                      podread: "Access your PodRead account"
                    }
                  }
                }
              }
            }
          },
          security: [
            { oauth2: [ "podread" ] }
          ]
        }
      end

      def create_episode_operation
        {
          operationId: "createEpisode",
          summary: "Create a podcast episode",
          description: "Convert an article URL or text into a podcast episode. Returns immediately with an episode ID — audio is generated asynchronously. Poll getEpisode to check status.",
          requestBody: {
            required: true,
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  required: [ "source_type" ],
                  properties: {
                    source_type: {
                      type: "string",
                      enum: [ "url", "text" ],
                      description: "How to create the episode. Use 'url' for a web article or 'text' for pasted content."
                    },
                    url: {
                      type: "string",
                      format: "uri",
                      description: "The article URL to convert. Required when source_type is 'url'."
                    },
                    text: {
                      type: "string",
                      description: "The text content to convert. Required when source_type is 'text'. Minimum 100 characters."
                    },
                    title: {
                      type: "string",
                      description: "Episode title. Required when source_type is 'text', auto-extracted for URLs."
                    },
                    author: {
                      type: "string",
                      description: "Author name. Optional."
                    },
                    voice: {
                      type: "string",
                      description: "Voice ID from listVoices. Falls back to the user's default voice if omitted."
                    }
                  }
                }
              }
            }
          },
          responses: {
            "201" => {
              description: "Episode created. Audio generation is in progress.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      id: { type: "string", description: "Episode ID (e.g. ep_abc123). Use this to poll status." }
                    }
                  }
                }
              }
            },
            "403" => { description: "Episode limit reached. Upgrade plan." },
            "422" => { description: "Invalid parameters (missing URL, text too short, etc)." },
            "429" => { description: "Rate limited. Too many episodes created recently." }
          }
        }
      end

      def list_episodes_operation
        {
          operationId: "listEpisodes",
          summary: "List your episodes",
          description: "Returns a paginated list of your podcast episodes, newest first.",
          parameters: [
            {
              name: "page",
              in: "query",
              schema: { type: "integer", default: 1 },
              description: "Page number."
            },
            {
              name: "limit",
              in: "query",
              schema: { type: "integer", default: 20, maximum: 100 },
              description: "Episodes per page. Max 100."
            }
          ],
          responses: {
            "200" => {
              description: "Paginated episode list.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      episodes: {
                        type: "array",
                        items: { "$ref" => "#/components/schemas/Episode" }
                      },
                      meta: { "$ref" => "#/components/schemas/PaginationMeta" }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def get_episode_operation
        {
          operationId: "getEpisode",
          summary: "Get episode details",
          description: "Returns details for a single episode. Use this to check processing status after creating an episode.",
          parameters: [
            {
              name: "id",
              in: "path",
              required: true,
              schema: { type: "string" },
              description: "Episode ID (e.g. ep_abc123)."
            }
          ],
          responses: {
            "200" => {
              description: "Episode details.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      episode: { "$ref" => "#/components/schemas/Episode" }
                    }
                  }
                }
              }
            },
            "404" => { description: "Episode not found." }
          }
        }
      end

      def delete_episode_operation
        {
          operationId: "deleteEpisode",
          summary: "Delete an episode",
          description: "Remove an episode from your feed. Deletion is processed asynchronously.",
          parameters: [
            {
              name: "id",
              in: "path",
              required: true,
              schema: { type: "string" },
              description: "Episode ID to delete (e.g. ep_abc123)."
            }
          ],
          responses: {
            "200" => {
              description: "Episode deletion started.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      deleted: { type: "boolean" }
                    }
                  }
                }
              }
            },
            "404" => { description: "Episode not found." }
          }
        }
      end

      def list_voices_operation
        {
          operationId: "listVoices",
          summary: "List available voices",
          description: "Returns voices available for your account tier. Pass a voice ID to createEpisode to choose a specific voice.",
          responses: {
            "200" => {
              description: "Available voices.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      voices: {
                        type: "array",
                        items: { "$ref" => "#/components/schemas/Voice" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def get_feed_operation
        {
          operationId: "getFeed",
          summary: "Get your podcast feed URL",
          description: "Returns the RSS feed URL for your podcast. Add this to any podcast app to listen to your episodes.",
          responses: {
            "200" => {
              description: "Feed URL.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      feed_url: { type: "string", format: "uri", description: "RSS feed URL." }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def get_auth_status_operation
        {
          operationId: "getAuthStatus",
          summary: "Check account status",
          description: "Returns your account email, plan tier, remaining credits, and character limit. Useful for checking what you can do.",
          responses: {
            "200" => {
              description: "Account status.",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      email: { type: "string", format: "email" },
                      tier: { type: "string", enum: [ "free", "premium", "unlimited" ] },
                      credits_remaining: { type: "integer", nullable: true },
                      character_limit: { type: "integer", nullable: true }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def schemas
        {
          Episode: {
            type: "object",
            properties: {
              id: { type: "string", description: "Episode ID (e.g. ep_abc123)." },
              title: { type: "string" },
              author: { type: "string", nullable: true },
              description: { type: "string", nullable: true },
              status: {
                type: "string",
                enum: [ "pending", "processing", "complete", "failed" ],
                description: "Processing status. Poll until 'complete' or 'failed'."
              },
              source_type: { type: "string", enum: [ "url", "paste", "extension" ] },
              source_url: { type: "string", nullable: true },
              duration_seconds: { type: "integer", nullable: true, description: "Audio duration. Present when status is 'complete'." },
              error_message: { type: "string", nullable: true, description: "Error details. Present when status is 'failed'." },
              created_at: { type: "string", format: "date-time" }
            }
          },
          Voice: {
            type: "object",
            properties: {
              id: { type: "string", description: "Voice ID to pass to createEpisode." },
              name: { type: "string" },
              accent: { type: "string" },
              gender: { type: "string" }
            }
          },
          PaginationMeta: {
            type: "object",
            properties: {
              page: { type: "integer" },
              limit: { type: "integer" },
              total: { type: "integer" }
            }
          }
        }
      end
    end
  end
end
