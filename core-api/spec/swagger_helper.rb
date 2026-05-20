require "rails_helper"

RSpec.configure do |config|
  # openapi_root is the directory where rswag:specs:swaggerize writes the
  # generated file. The key in openapi_specs is appended to this path, so
  # setting the key to "openapi.yaml" and root to Rails.root.join("..") means
  # the file lands at core-api/../openapi.yaml == repo-root/core-api/openapi.yaml
  # (i.e., it overwrites the hand-maintained file).
  config.openapi_root = Rails.root.to_s

  config.openapi_format = :yaml

  # rswag_dry_run = false so that run_test! actually fires HTTP requests and
  # validates responses, not just generates the spec skeleton.
  config.rswag_dry_run = false

  config.openapi_specs = {
    "openapi.yaml" => {
      openapi: "3.1.0",
      info: {
        title: "EHS Incident System API",
        version: "1.0.0",
        description: <<~DESC.strip
          REST API for the EHS Incident Management System (core-api).
          All endpoints under /api/v1 require a Bearer JWT in the Authorization
          header except the /auth/* endpoints. Errors follow RFC 7807
          problem+json.

          Generated via `bundle exec rake rswag:specs:swaggerize`. Do not edit
          by hand — edit the request specs instead.
        DESC
      },
      servers: [
        { url: "http://localhost:3000", description: "Local dev (docker-compose)" },
        { url: "https://api.ehs.example.com", description: "Production placeholder" }
      ],
      security: [ { bearerAuth: [] } ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT"
          }
        },
        schemas: {
          Problem: {
            type: "object",
            description: "RFC 7807 problem+json error envelope",
            properties: {
              type:     { type: "string" },
              title:    { type: "string" },
              status:   { type: "integer" },
              detail:   { type: "string" },
              instance: { type: "string" }
            }
          },
          UserAttributes: {
            type: "object",
            properties: {
              email:           { type: "string", format: "email" },
              name:            { type: "string" },
              role:            { type: "string", enum: %w[worker investigator admin] },
              organization_id: { type: "integer" },
              confirmed_at:    { type: "string", format: "date-time", nullable: true },
              locked_at:       { type: "string", format: "date-time", nullable: true },
              deleted_at:      { type: "string", format: "date-time", nullable: true }
            }
          },
          IncidentAttributes: {
            type: "object",
            properties: {
              state:         { type: "string", enum: %w[draft submitted investigating pending_closure closed] },
              incident_type: { type: "string" },
              severity:      { type: "integer", minimum: 1, maximum: 5 },
              occurred_at:   { type: "string", format: "date-time" },
              location:      { type: "string" },
              summary:       { type: "string" },
              description:   { type: "string" },
              root_cause:    { type: "string", nullable: true },
              submitted_at:  { type: "string", format: "date-time", nullable: true },
              triaged_at:    { type: "string", format: "date-time", nullable: true },
              closed_at:     { type: "string", format: "date-time", nullable: true },
              site_id:       { type: "integer" },
              reporter_id:   { type: "integer" },
              assignee_id:   { type: "integer", nullable: true }
            }
          },
          CorrectiveActionAttributes: {
            type: "object",
            properties: {
              title:        { type: "string" },
              description:  { type: "string" },
              state:        { type: "string", enum: %w[open in_progress done verified cancelled] },
              due_date:     { type: "string", format: "date-time" },
              completed_at: { type: "string", format: "date-time", nullable: true },
              verified_at:  { type: "string", format: "date-time", nullable: true },
              overdue:      { type: "boolean" },
              assignee_id:  { type: "integer" },
              incident_id:  { type: "integer" }
            }
          },
          DashboardAttributes: {
            type: "object",
            properties: {
              open_incidents_by_severity: {
                type: "object",
                additionalProperties: { type: "integer" }
              },
              incidents_by_state: {
                type: "object",
                additionalProperties: { type: "integer" }
              },
              overdue_corrective_actions_count: { type: "integer" },
              last_30_day_incidents_trend: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    date:  { type: "string", format: "date" },
                    count: { type: "integer" }
                  }
                }
              },
              avg_time_to_close_seconds: { type: "number", nullable: true },
              sla_compliance: {
                type: "object",
                additionalProperties: { type: "string" }
              }
            }
          }
        }
      }
    }
  }
end
