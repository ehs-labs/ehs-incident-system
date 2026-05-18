require "swagger_helper"

RSpec.describe "Auth API", type: :request do
  path "/api/v1/auth/signup" do
    post "Create a new tenant + admin user" do
      tags "auth"
      consumes "application/json"
      produces "application/json"
      security []

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            required: %w[email password name],
            properties: {
              email:             { type: :string, format: :email },
              password:          { type: :string },
              name:              { type: :string },
              organization_name: { type: :string }
            }
          }
        },
        required: ["user"]
      }

      response "201", "Created — JWT in Authorization header" do
        let(:body) do
          { user: { email: "admin@example.com", password: "P!ssw0rd1234", name: "Alice" } }
        end

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["access_token"]).to be_present
          expect(data.dig("user", "data", "attributes", "role")).to eq("admin")
        end
      end

      response "422", "Validation failed (e.g. duplicate email)" do
        let!(:existing_org)  { create(:organization) }
        let!(:existing_user) { create(:user, organization: existing_org, email: "admin@example.com", confirmed_at: Time.current) }
        let(:body) do
          { user: { email: "admin@example.com", password: "P!ssw0rd1234", name: "Bob" } }
        end

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.content_type).to start_with("application/problem+json")
        end
      end
    end
  end

  path "/api/v1/auth/login" do
    post "Exchange credentials for a JWT" do
      tags "auth"
      consumes "application/json"
      produces "application/json"
      security []

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            required: %w[email password],
            properties: {
              email:    { type: :string, format: :email },
              password: { type: :string }
            }
          }
        },
        required: ["user"]
      }

      let(:org)  { create(:organization) }
      let(:user) { create(:user, organization: org, email: "login@example.com", password: "P!ssw0rd1234", confirmed_at: Time.current) }

      response "200", "OK — JWT in Authorization header" do
        let(:body) { { user: { email: user.email, password: "P!ssw0rd1234" } } }

        run_test! do |response|
          data = JSON.parse(response.body)
          expect(data["access_token"]).to be_present
        end
      end

      response "401", "Invalid credentials" do
        let(:body) { { user: { email: user.email, password: "wrong!" } } }

        produces "application/problem+json"
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.content_type).to start_with("application/problem+json")
          expect(JSON.parse(response.body)["title"]).to eq("Invalid credentials")
        end
      end
    end
  end

  path "/api/v1/auth/logout" do
    delete "Revoke the current JWT" do
      tags "auth"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:org)           { create(:organization) }
      let(:user)          { create(:user, organization: org, confirmed_at: Time.current) }
      let(:Authorization) { "Bearer #{Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first}" }

      response "204", "No Content" do
        run_test!
      end
    end
  end
end
