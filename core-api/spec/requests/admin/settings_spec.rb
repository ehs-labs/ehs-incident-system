require "swagger_helper"

RSpec.describe "Admin Settings API", type: :request do
  let(:organization) { create(:organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/admin/settings" do
    get "Return organization SLA settings" do
      tags "admin/settings"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK — returns empty overrides initially" do
        run_test! do |response|
          expect(JSON.parse(response.body).dig("data", "attributes", "sla_overrides")).to eq({})
        end
      end

      response "403", "Forbidden — worker cannot access settings" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end

    patch "Update organization SLA overrides" do
      tags "admin/settings"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          setting: {
            type: :object,
            properties: {
              sla_overrides: {
                type: :object,
                additionalProperties: {
                  type: :object,
                  properties: {
                    triage_seconds: { type: :integer }
                  }
                }
              }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }
      let(:body) { { setting: { sla_overrides: { "1" => { "triage_seconds" => 7200 } } } } }

      response "200", "OK — updated overrides flow into Incident#triage_sla" do
        run_test! do |response|
          expect(JSON.parse(response.body).dig("data", "attributes", "sla_overrides", "1", "triage_seconds")).to eq(7200)

          site     = create(:site, organization: organization)
          reporter = create(:user, organization: organization)
          incident = create(:incident, organization: organization, site: site, reporter: reporter, severity: 1)
          expect(incident.triage_sla.to_i).to eq(7200)
        end
      end
    end
  end
end
