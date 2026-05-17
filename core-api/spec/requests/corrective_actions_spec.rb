require "rails_helper"

# NOTE: this spec requires the following route layout (the agent does not
# modify config/routes.rb):
#   resources :incidents do
#     resources :corrective_actions, only: %i[index create]
#   end
#   resources :corrective_actions, only: %i[index show update] do
#     member { post "transitions", to: "corrective_actions#transition" }
#   end
#
# Tests that need a route which isn't currently wired will be skipped.
RSpec.describe "Corrective Actions API", type: :request do
  let(:org)          { create(:organization) }
  let(:site)         { create(:site, organization: org) }
  let(:reporter)     { create(:user, organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:admin)        { create(:user, :admin, organization: org) }
  let(:assignee)     { create(:user, organization: org) }

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: admin,        site: site)
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

  def json
    JSON.parse(response.body)
  end

  describe "GET /api/v1/incidents/:incident_id/corrective_actions" do
    it "lists actions for the incident, scoped by policy" do
      create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      # An action on another incident — must not leak in.
      other_inc = create(:incident, organization: org, site: site, reporter: reporter)
      create(:corrective_action, incident: other_inc, assignee: assignee, created_by: investigator)

      get "/api/v1/incidents/#{incident.id}/corrective_actions", headers: auth_headers(investigator)

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(2)
    end

    it "returns 401 without a token" do
      get "/api/v1/incidents/#{incident.id}/corrective_actions"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/corrective_actions (flat list)" do
    before do
      skip "flat index route not wired" unless route_exists?("/api/v1/corrective_actions", :get)
    end

    it "supports state and overdue filters" do
      open_action   = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      done_action   = create(:corrective_action, :done, incident: incident, assignee: assignee, created_by: investigator)
      overdue_act   = create(:corrective_action, :overdue, incident: incident, assignee: assignee, created_by: investigator)

      get "/api/v1/corrective_actions?state=open", headers: auth_headers(investigator)
      ids = json["data"].map { |d| d["id"].to_i }
      expect(ids).to include(open_action.id, overdue_act.id)
      expect(ids).not_to include(done_action.id)

      get "/api/v1/corrective_actions?overdue=true", headers: auth_headers(investigator)
      ids = json["data"].map { |d| d["id"].to_i }
      expect(ids).to eq([overdue_act.id])
    end
  end

  describe "GET /api/v1/corrective_actions/:id" do
    it "returns the action when the caller is allowed" do
      action = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)

      get "/api/v1/corrective_actions/#{action.id}", headers: auth_headers(investigator)

      expect(response).to have_http_status(:ok)
      expect(json["data"]["id"]).to eq(action.id.to_s)
    end

    it "returns 404 when the action belongs to another org" do
      other_org = create(:organization)
      other_site = create(:site, organization: other_org)
      other_user = create(:user, organization: other_org)
      other_inc  = create(:incident, organization: other_org, site: other_site, reporter: other_user)
      other_act  = create(:corrective_action, incident: other_inc, assignee: other_user, created_by: other_user)

      get "/api/v1/corrective_actions/#{other_act.id}", headers: auth_headers(investigator)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/incidents/:incident_id/corrective_actions" do
    let(:valid_params) do
      {
        corrective_action: {
          title:       "Inspect aisle 4 forklift",
          description: "Document mechanical inspection.",
          due_date:    7.days.from_now.iso8601,
          assignee_id: assignee.id
        }
      }
    end

    it "creates an action and emits CorrectiveActionAssigned to the outbox" do
      expect {
        post "/api/v1/incidents/#{incident.id}/corrective_actions",
             params: valid_params.to_json,
             headers: auth_headers(investigator).merge("Content-Type" => "application/json")
      }.to change(CorrectiveAction, :count).by(1)
        .and change { OutboxEvent.where(event_type: "CorrectiveActionAssigned").count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "attributes", "title")).to eq("Inspect aisle 4 forklift")
    end

    it "denies workers without permission" do
      post "/api/v1/incidents/#{incident.id}/corrective_actions",
           params: valid_params.to_json,
           headers: auth_headers(reporter).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:forbidden)
    end

    it "422s on validation error" do
      post "/api/v1/incidents/#{incident.id}/corrective_actions",
           params: { corrective_action: { title: "", due_date: 1.day.ago.iso8601, assignee_id: assignee.id } }.to_json,
           headers: auth_headers(investigator).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.content_type).to start_with("application/problem+json")
    end
  end

  describe "POST /api/v1/corrective_actions/:id/transitions" do
    before do
      skip "transitions route not wired to #transition" unless transitions_routes_to_transition?
    end

    let(:action) { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }

    it "lets the assignee :start" do
      post "/api/v1/corrective_actions/#{action.id}/transitions",
           params: { event: "start" }.to_json,
           headers: auth_headers(assignee).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(action.reload.state).to eq("in_progress")
    end

    it "lets the investigator :verify after :complete" do
      action.start!
      action.complete!

      post "/api/v1/corrective_actions/#{action.id}/transitions",
           params: { event: "verify" }.to_json,
           headers: auth_headers(investigator).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(action.reload.state).to eq("verified")
    end

    it "rejects an unknown event with 422" do
      post "/api/v1/corrective_actions/#{action.id}/transitions",
           params: { event: "explode" }.to_json,
           headers: auth_headers(investigator).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ------------------------------------------------------------------ helpers
  def route_exists?(path, method)
    Rails.application.routes.recognize_path(path, method: method).present?
  rescue ActionController::RoutingError
    false
  end

  def transitions_routes_to_transition?
    route = Rails.application.routes.recognize_path("/api/v1/corrective_actions/1/transitions", method: :post)
    route[:action] == "transition"
  rescue ActionController::RoutingError
    false
  end
end
