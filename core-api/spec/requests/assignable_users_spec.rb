require "swagger_helper"

RSpec.describe "Assignable Users API", type: :request do
  let(:organization) { create(:organization) }
  let(:other_org)    { create(:organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:worker)       { create(:user, organization: organization) }

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/assignable_users" do
    get "List users assignable to incidents and corrective actions" do
      tags "assignable_users"
      produces "application/json"
      security [ { bearerAuth: [] } ]

      parameter name: :q, in: :query, schema: { type: :string }, required: false

      response "200", "OK — admin sees own organization users" do
        let(:Authorization) { "Bearer #{jwt_for(admin)}" }
        let(:cross_org_user) { create(:user, organization: other_org) }
        let(:_peer)          { create(:user, organization: organization) }

        before { cross_org_user; _peer }

        run_test! do |response|
          ids = JSON.parse(response.body)["data"].map { |u| u["id"].to_i }
          expect(ids).to include(admin.id, _peer.id)
          expect(ids).not_to include(cross_org_user.id)
        end
      end

      response "200", "OK — investigator sees own organization users" do
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }
        let(:cross_org_user) { create(:user, organization: other_org) }

        before { worker; cross_org_user }

        run_test! do |response|
          data = JSON.parse(response.body)["data"]
          ids = data.map { |u| u["id"].to_i }
          expect(ids).to include(investigator.id, worker.id)
          expect(ids).not_to include(cross_org_user.id)
        end
      end

      response "200", "OK — soft-deleted and locked users are excluded" do
        let(:Authorization)   { "Bearer #{jwt_for(investigator)}" }
        let(:deleted_user)    { create(:user, organization: organization) }
        let(:locked_user)     { create(:user, organization: organization) }

        before do
          deleted_user.soft_delete!
          locked_user.lock_access!
        end

        run_test! do |response|
          ids = JSON.parse(response.body)["data"].map { |u| u["id"].to_i }
          expect(ids).not_to include(deleted_user.id, locked_user.id)
        end
      end

      response "200", "OK — payload exposes only id, name, email, role" do
        let(:Authorization) { "Bearer #{jwt_for(investigator)}" }

        run_test! do |response|
          attrs = JSON.parse(response.body)["data"].first["attributes"]
          expect(attrs.keys).to match_array(%w[name email role])
        end
      end

      response "403", "Forbidden — worker cannot list assignable users" do
        let(:Authorization) { "Bearer #{jwt_for(worker)}" }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(403)
        end
      end

      response "401", "Unauthorized — missing JWT" do
        let(:Authorization) { nil }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(401)
        end
      end
    end
  end
end
