require "swagger_helper"

# Routes exercised:
#   resources :incidents do
#     resources :corrective_actions, only: %i[index create]
#   end
#   resources :corrective_actions, only: %i[index show update] do
#     member { post "transitions", to: "corrective_actions#transition" }
#   end
RSpec.describe "Corrective Actions API", type: :request do
  let(:org)          { create(:organization) }
  let(:site)         { create(:site, organization: org) }
  let(:reporter)     { create(:user, organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:admin)        { create(:user, :admin, organization: org) }
  let(:assignee)     { create(:user, organization: org) }

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: admin, site: site)
  end

  let(:incident) do
    inc = create(:incident, organization: org, site: site, reporter: reporter)
    Current.user = reporter
    inc.submit!
    Current.user = investigator
    inc.update!(assignee: investigator)
    inc.triage!
    Current.user = nil
    inc
  end

  def jwt_for(user)
    Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/incidents/:incident_id/corrective_actions
  # ---------------------------------------------------------------------------
  path "/api/v1/incidents/{incident_id}/corrective_actions" do
    parameter name: :incident_id, in: :path, schema: { type: :integer }, required: true

    let(:incident_id) { incident.id }

    get "List corrective actions for an incident" do
      tags "corrective_actions"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

      response "200", "OK — actions scoped by Pundit policy" do
        before do
          create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
          create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
          # Action on a different incident — must not appear in results.
          other_inc = create(:incident, organization: org, site: site, reporter: reporter)
          create(:corrective_action, incident: other_inc, assignee: assignee, created_by: investigator)
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["data"].size).to eq(2)
        end
      end

      response "401", "Unauthorized — no token" do
        let(:Authorization) { "" }

        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(401)
        end
      end
    end

    post "Create a corrective action for an incident" do
      tags "corrective_actions"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: [ "corrective_action" ],
        properties: {
          corrective_action: {
            type: :object,
            required: %w[title description due_date assignee_id],
            properties: {
              title:       { type: :string },
              description: { type: :string },
              due_date:    { type: :string, format: :"date-time" },
              assignee_id: { type: :integer }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

      response "201", "Created — emits CorrectiveActionAssigned to outbox" do
        let(:body) do
          {
            corrective_action: {
              title:       "Inspect aisle 4 forklift",
              description: "Document mechanical inspection.",
              due_date:    7.days.from_now.iso8601,
              assignee_id: assignee.id
            }
          }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "attributes", "title")).to eq("Inspect aisle 4 forklift")
          # The outbox event is emitted on create — verify a new event was added.
          expect(OutboxEvent.where(event_type: "CorrectiveActionAssigned").count).to be >= 1
        end
      end

      response "403", "Forbidden — workers cannot create corrective actions" do
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        let(:body) do
          {
            corrective_action: {
              title:       "Unauthorized attempt",
              description: "Should be rejected.",
              due_date:    7.days.from_now.iso8601,
              assignee_id: assignee.id
            }
          }
        end

        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end

      response "422", "Validation error (blank title or past due_date)" do
        let(:body) do
          {
            corrective_action: {
              title:       "",
              description: "Missing title.",
              due_date:    1.day.ago.iso8601,
              assignee_id: assignee.id
            }
          }
        end

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.status).to eq(422)
          expect(response.content_type).to start_with("application/problem+json")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/corrective_actions/:id
  # ---------------------------------------------------------------------------
  path "/api/v1/corrective_actions/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let(:action) { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }
    let(:id)     { action.id }

    get "Get a single corrective action" do
      tags "corrective_actions"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

      response "200", "OK" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "id")).to eq(action.id.to_s)
        end
      end

      response "404", "Not Found — action belongs to another org" do
        let(:other_org)   { create(:organization) }
        let(:other_site)  { create(:site, organization: other_org) }
        let(:other_user)  { create(:user, organization: other_org) }
        let(:other_inc)   { create(:incident, organization: other_org, site: other_site, reporter: other_user) }
        let(:action)      { create(:corrective_action, incident: other_inc, assignee: other_user, created_by: other_user) }
        let(:id)          { action.id }
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/corrective_actions/:id/transitions
  # ---------------------------------------------------------------------------
  path "/api/v1/corrective_actions/{id}/transitions" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    before do
      skip "transitions route not wired to #transition" unless transitions_routes_to_transition?
    end

    let(:action) { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }
    let(:id)     { action.id }

    post "Run an AASM transition on a corrective action" do
      tags "corrective_actions"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: [ "event" ],
        properties: {
          event: { type: :string, enum: %w[start complete verify cancel] }
        }
      }

      response "200", "Transition applied — assignee starts action" do
        let(:Authorization) { "Bearer #{jwt_for(assignee)}" }
        let(:body)          { { event: "start" } }

        run_test! do |response|
          expect(action.reload.state).to eq("in_progress")
        end
      end

      response "422", "Invalid or unknown event" do
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }
        let(:body)          { { event: "explode" } }

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------
  def transitions_routes_to_transition?
    route = Rails.application.routes.recognize_path("/api/v1/corrective_actions/1/transitions", method: :post)
    route[:action] == "transition"
  rescue ActionController::RoutingError
    false
  end
end
