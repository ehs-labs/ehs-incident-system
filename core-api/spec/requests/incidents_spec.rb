require "swagger_helper"

RSpec.describe "Incidents API", type: :request do
  let(:org)          { create(:organization) }
  let(:site)         { create(:site, organization: org) }
  let(:reporter)     { create(:user, organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:admin)        { create(:user, :admin, organization: org) }

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: admin, site: site)
  end

  def jwt_for(user)
    Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
  end

  path "/api/v1/incidents" do
    get "List incidents (paginated, Pundit-scoped)" do
      tags "incidents"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :state,    in: :query, schema: { type: :string },  required: false
      parameter name: :severity, in: :query, schema: { type: :integer }, required: false
      parameter name: :site_id,  in: :query, schema: { type: :integer }, required: false
      parameter name: :q,        in: :query, schema: { type: :string },  required: false
      parameter name: :page,     in: :query, schema: { type: :integer }, required: false
      parameter name: :per_page, in: :query, schema: { type: :integer }, required: false

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK" do
        before { create(:incident, organization: org, site: site, reporter: reporter) }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["data"]).to be_an(Array)
          expect(data["data"].size).to be >= 1

          included_types = data["included"].to_a.map { |r| r["type"] }
          expect(included_types).to include("site", "user")
        end
      end

      response "401", "Unauthorized — no or invalid token" do
        let(:Authorization) { "" }

        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(401)
        end
      end
    end

    post "Create a new (draft) incident" do
      tags "incidents"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: ["incident"],
        properties: {
          incident: {
            type: :object,
            required: %w[site_id incident_type severity occurred_at location summary description],
            properties: {
              site_id:       { type: :integer },
              incident_type: { type: :string },
              severity:      { type: :integer, minimum: 1, maximum: 5 },
              occurred_at:   { type: :string, format: :"date-time" },
              location:      { type: :string },
              summary:       { type: :string },
              description:   { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }

      response "201", "Created" do
        let(:body) do
          {
            incident: {
              site_id:       site.id,
              incident_type: "slip",
              severity:      3,
              occurred_at:   1.hour.ago.iso8601,
              location:      "Hall A",
              summary:       "Slip near entrance",
              description:   "A worker slipped on a wet floor."
            }
          }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "attributes", "state")).to eq("draft")
          expect(data.dig("data", "attributes", "summary")).to eq("Slip near entrance")
        end
      end

      response "422", "Validation error" do
        let(:body) { { incident: { site_id: site.id, severity: 99 } } }

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end
    end
  end

  path "/api/v1/incidents/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }
    let(:id)       { incident.id }

    get "Get an incident" do
      tags "incidents"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }

      response "200", "OK" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "id")).to eq(incident.id.to_s)

          included_types = data["included"].to_a.map { |r| r["type"] }
          expect(included_types).to include("site", "user")

          site_record = data["included"].find { |r| r["type"] == "site" && r["id"] == site.id.to_s }
          expect(site_record).not_to be_nil
        end
      end

      response "404", "Not Found — incident not in caller's Pundit scope" do
        let(:other_org)  { create(:organization) }
        let(:other_user) { create(:user, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(other_user)}" }

        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end

    patch "Update an incident" do
      tags "incidents"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          incident: {
            type: :object,
            properties: {
              summary:     { type: :string },
              description: { type: :string },
              severity:    { type: :integer, minimum: 1, maximum: 5 }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
      let(:body)          { { incident: { summary: "Updated summary" } } }

      response "200", "OK" do
        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "attributes", "summary")).to eq("Updated summary")
        end
      end
    end
  end

  path "/api/v1/incidents/{id}/transitions" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }
    let(:id)       { incident.id }

    post "Run an AASM state transition" do
      tags "incidents"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: ["event"],
        properties: {
          event:       { type: :string, enum: %w[submit triage verify close reopen] },
          assignee_id: { type: :integer },
          severity:    { type: :integer }
        }
      }

      response "200", "Transition applied" do
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        let(:body)          { { event: "submit" } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data.dig("data", "attributes", "state")).to eq("submitted")
        end
      end

      response "422", "Invalid transition or unknown event" do
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        let(:body)          { { event: "explode" } }

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end

      response "403", "Forbidden — caller authorized to see the incident but not perform this transition" do
        # The reporter already submitted; a second submit attempt raises
        # a Pundit::NotAuthorizedError (not 404) because the incident IS in
        # the reporter's policy_scope but the submit? guard fails.
        let(:submitted_incident) do
          Current.user = reporter
          incident.submit!
          Current.user = nil
          incident
        end
        let(:id)            { submitted_incident.id }
        let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
        let(:body)          { { event: "submit" } }

        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end
end
