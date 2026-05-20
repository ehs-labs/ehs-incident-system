require "swagger_helper"

RSpec.describe "Admin Users API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/admin/users" do
    get "List users in the organization" do
      tags "admin/users"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :role, in: :query, schema: { type: :string }, required: false
      parameter name: :q,    in: :query, schema: { type: :string }, required: false

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK — lists users scoped to own organization" do
        let(:other_org_user) { create(:user, organization: create(:organization)) }
        let(:_peer) { create(:user, organization: organization) }

        before { other_org_user; _peer }

        run_test! do |response|
          ids = JSON.parse(response.body)["data"].map { |u| u["id"].to_i }
          expect(ids).to include(admin.id)
          expect(ids).not_to include(other_org_user.id)
        end
      end

      response "200", "OK — filtered by role" do
        let(:role) { "investigator" }

        before { worker; investigator }

        run_test! do |response|
          roles = JSON.parse(response.body)["data"].map { |u| u.dig("attributes", "role") }
          expect(roles.uniq).to eq([ "investigator" ])
        end
      end

      response "200", "OK — filtered by q (email/name)" do
        let(:q)      { "findable" }
        let(:target) { create(:user, organization: organization, name: "Findable Person", email: "findable@example.com") }

        before { target }

        run_test! do |response|
          ids = JSON.parse(response.body)["data"].map { |u| u["id"].to_i }
          expect(ids).to include(target.id)
        end
      end

      response "403", "Forbidden — worker cannot list users" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  path "/api/v1/admin/users/invite" do
    post "Invite a new user via email" do
      tags "admin/users"
      consumes "application/json"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          user: {
            type: :object,
            required: %w[email name role],
            properties: {
              email:    { type: :string, format: :email },
              name:     { type: :string },
              role:     { type: :string, enum: %w[worker investigator admin] },
              site_ids: { type: :array, items: { type: :integer } }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "201", "Created — invitation email sent and sites assigned" do
        let(:body) do
          { user: { email: "newhire@example.com", name: "New Hire", role: "worker", site_ids: [ site.id ] } }
        end

        run_test! do |response|
          expect(ActionMailer::Base.deliveries.count).to be >= 1
          invited = User.find_by(email: "newhire@example.com")
          expect(invited.invitation_token).to be_present
          expect(invited.sites).to include(site)
        end
      end

      response "403", "Forbidden — investigator cannot invite users" do
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }
        let(:body) { { user: { email: "x@example.com", name: "x", role: "worker" } } }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  path "/api/v1/admin/users/{id}/lock" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true
    let(:id) { worker.id }

    post "Lock a user account" do
      tags "admin/users"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "200", "OK — user is locked" do
        run_test! do |response|
          expect(worker.reload.access_locked?).to be(true)
        end
      end

      response "403", "Forbidden — worker cannot lock accounts" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        let(:id) { investigator.id }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end
    end
  end

  path "/api/v1/admin/users/{id}/unlock" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true
    let(:id) { worker.id }

    post "Unlock a user account" do
      tags "admin/users"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      before do
        worker.lock_access!
      end

      response "200", "OK — user is unlocked" do
        run_test! do |response|
          expect(worker.reload.access_locked?).to be(false)
        end
      end
    end
  end

  path "/api/v1/admin/users/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true
    let(:id) { worker.id }

    delete "Soft-delete a user" do
      tags "admin/users"
      security [ { bearerAuth: [] } ]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "204", "No Content — user soft-deleted" do
        run_test! do |response|
          expect(worker.reload.deleted_at).to be_present
        end
      end
    end
  end
end
