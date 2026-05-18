require "swagger_helper"

RSpec.describe "Comments API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/incidents/{incident_id}/comments" do
    parameter name: :incident_id, in: :path, schema: { type: :integer }, required: true
    let(:incident_id) { incident.id }

    get "List comments on an incident" do
      tags "comments"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }
      let!(:comment) { create(:comment, incident: incident, author: investigator) }

      response "200", "OK" do
        run_test! do |response|
          data = JSON.parse(response.body).fetch("data")
          expect(data.size).to eq(1)
          expect(data.first.dig("attributes", "body")).to eq(comment.body)
        end
      end
    end

    post "Add a comment to an incident" do
      tags "comments"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          comment: {
            type: :object,
            required: ["body"],
            properties: {
              body: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }

      response "201", "Created — author is set from current user, not params" do
        let(:body) { { comment: { body: "First comment", author_id: admin.id } } }

        run_test! do |response|
          created = Comment.last
          expect(created.author_id).to eq(reporter.id)
          expect(created.body).to eq("First comment")
        end
      end

      response "404", "Not Found — unrelated worker cannot see the incident" do
        let(:other_worker) { create(:user, organization: organization) }
        let(:Authorization) { "Bearer #{jwt_for(other_worker)}" }
        let(:body) { { comment: { body: "sneaky" } } }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end

      response "422", "Unprocessable — empty body" do
        let(:body) { { comment: { body: "" } } }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end
    end
  end

  path "/api/v1/comments/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let!(:own_comment) { create(:comment, incident: incident, author: reporter, body: "old") }
    let(:id)           { own_comment.id }

    patch "Update a comment" do
      tags "comments"
      consumes "application/json"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          comment: {
            type: :object,
            properties: {
              body: { type: :string }
            }
          }
        }
      }

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }
      let(:body)          { { comment: { body: "new" } } }

      response "200", "OK — author updates their own comment" do
        run_test! do |response|
          expect(own_comment.reload.body).to eq("new")
        end
      end

      response "404", "Not Found — unrelated worker cannot see the comment" do
        let(:other_worker) { create(:user, organization: organization) }
        let(:Authorization) { "Bearer #{jwt_for(other_worker)}" }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end

      response "200", "OK — admin can edit any comment" do
        let(:Authorization) { "Bearer #{jwt_for(admin)}" }
        let(:body)          { { comment: { body: "edited by admin" } } }

        run_test! do |response|
          expect(own_comment.reload.body).to eq("edited by admin")
        end
      end
    end

    delete "Delete a comment" do
      tags "comments"
      security [{ bearerAuth: [] }]

      let!(:authored_comment) { create(:comment, incident: incident, author: investigator) }
      let(:id)                { authored_comment.id }
      let(:Authorization)     { "Bearer #{jwt_for(investigator)}" }

      response "204", "No Content — author deletes their own comment" do
        run_test! do |response|
          expect(response.status).to eq(204)
        end
      end
    end
  end
end
