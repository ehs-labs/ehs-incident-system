require "swagger_helper"

RSpec.describe "Me API", type: :request do
  let(:organization) { create(:organization, slug: "acme-co") }
  let(:site)         { create(:site, organization: organization, name: "Plant 1", timezone: "Australia/Sydney") }
  let(:user)         { create(:user, organization: organization, name: "Original Name") }

  before { create(:site_membership, user: user, site: site) }

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/me" do
    get "Return the current user's profile" do
      tags "me"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(user)}" }

      response "200", "OK" do
        run_test! do |response|
          attrs = JSON.parse(response.body).dig("data", "attributes")
          expect(attrs["email"]).to eq(user.email)
          expect(attrs["name"]).to eq("Original Name")
          expect(attrs["role"]).to eq("worker")
          expect(attrs["organization"]).to include("slug" => "acme-co")
          expect(attrs["sites"].first).to include("name" => "Plant 1", "timezone" => "Australia/Sydney")
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

    patch "Update the current user's name" do
      tags "me"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          me: {
            type: :object,
            properties: {
              name: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(user)}" }
      # email and role are ignored — only name is writable
      let(:body) { { me: { name: "New Name", email: "hacker@example.com", role: "admin" } } }

      response "200", "OK — only name is updated; email and role are ignored" do
        run_test! do |response|
          user.reload
          expect(user.name).to eq("New Name")
          expect(user.email).not_to eq("hacker@example.com")
          expect(user.role).to eq("worker")
        end
      end
    end
  end
end
