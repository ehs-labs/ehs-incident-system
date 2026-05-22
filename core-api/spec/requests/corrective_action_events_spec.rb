require "swagger_helper"

RSpec.describe "Corrective Action Events API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:assignee)     { create(:user, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, assignee: investigator) }
  let(:action)       { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:corrective_action_event, corrective_action: action, actor: investigator, event_name: "assigned", note: "Walkthrough finding")
    create(:corrective_action_event, corrective_action: action, actor: assignee,     event_name: "started",  note: nil)
    create(:corrective_action_event, corrective_action: action, actor: assignee,     event_name: "completed", note: "Replaced wheel")
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/corrective_actions/{corrective_action_id}/events" do
    parameter name: :corrective_action_id, in: :path, schema: { type: :integer }, required: true

    get "List events for a corrective action" do
      tags "corrective_actions"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:corrective_action_id) { action.id }
      let(:Authorization)        { "Bearer #{jwt_for(investigator)}" }

      response "200", "OK — chronological list, oldest first" do
        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          expect(data.map { |r| r["attributes"]["event_name"] }).to eq(%w[assigned started completed])
          expect(data.first["attributes"].keys).to match_array(%w[event_name note actor_id created_at])
          expect(data.first["attributes"]["note"]).to eq("Walkthrough finding")
        end
      end

      response "404", "Not Found — user from another org cannot see the action" do
        let(:other_org)     { create(:organization) }
        let(:outsider)      { create(:user, :admin, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(outsider)}" }
        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end

      response "404", "Not Found — action does not exist" do
        let(:corrective_action_id) { 0 }
        produces "application/problem+json"

        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end
  end
end
