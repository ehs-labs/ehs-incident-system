require "swagger_helper"

RSpec.describe "Attachments API", type: :request do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }
  let(:admin)        { create(:user, :admin, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter, state: "draft") }

  let(:fixture_path) { Rails.root.join("spec/fixtures/files/sample.png") }
  let(:upload)       { Rack::Test::UploadedFile.new(fixture_path.to_s, "image/png") }

  before do
    create(:site_membership, site: site, user: investigator)
    create(:site_membership, site: site, user: admin)
  end

  def jwt_for(u)
    Warden::JWTAuth::UserEncoder.new.call(u, :user, nil).first
  end

  path "/api/v1/incidents/{incident_id}/attachments" do
    parameter name: :incident_id, in: :path, schema: { type: :integer }, required: true
    let(:incident_id) { incident.id }

    post "Upload a file attachment to an incident" do
      tags "attachments"
      consumes "multipart/form-data"
      produces "application/json"
      security [{ bearerAuth: [] }]

      parameter name: :"attachment[file]", in: :formData, schema: { type: :string, format: :binary }, required: true

      let(:Authorization) { "Bearer #{jwt_for(reporter)}" }

      response "201", "Created — file attached to incident" do
        let(:"attachment[file]") { upload }

        run_test! do |response|
          expect(incident.reload.photos).to be_attached
          body = JSON.parse(response.body).fetch("data")
          expect(body.dig("attributes", "filename")).to eq("sample.png")
          expect(body.dig("attributes", "content_type")).to eq("image/png")
        end
      end

      response "422", "Unprocessable — no file provided" do
        let(:Authorization) { "Bearer #{jwt_for(admin)}" }
        let(:"attachment[file]") { nil }
        produces "application/problem+json"
        run_test! do |response|
          expect(response.status).to eq(422)
        end
      end

      response "404", "Not Found — user from another org cannot see the incident" do
        let(:other_org)   { create(:organization) }
        let(:other_admin) { create(:user, :admin, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(other_admin)}" }
        let(:"attachment[file]") { upload }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end

    get "List attachments on an incident" do
      tags "attachments"
      produces "application/json"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      before do
        incident.photos.attach(io: File.open(fixture_path), filename: "sample.png", content_type: "image/png")
      end

      response "200", "OK — lists attachments with proxy URLs" do
        run_test! do |response|
          body = JSON.parse(response.body).fetch("data")
          expect(body.size).to eq(1)
          attrs = body.first["attributes"]
          expect(attrs["url"]).to be_present
          expect(attrs["signed_id"]).to be_present
          expect(attrs["filename"]).to eq("sample.png")
        end
      end
    end
  end

  path "/api/v1/attachments/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    let(:attachment) do
      incident.photos.attach(io: File.open(fixture_path), filename: "sample.png", content_type: "image/png")
      incident.photos.attachments.last
    end
    let(:id) { attachment.id }

    delete "Purge an attachment" do
      tags "attachments"
      security [{ bearerAuth: [] }]

      let(:Authorization) { "Bearer #{jwt_for(admin)}" }

      response "204", "No Content — attachment purged" do
        run_test! do |response|
          expect(ActiveStorage::Attachment.where(id: id)).to be_empty
        end
      end

      response "404", "Not Found — user from another org cannot see the attachment" do
        let(:other_org)   { create(:organization) }
        let(:other_admin) { create(:user, :admin, organization: other_org) }
        let(:Authorization) { "Bearer #{jwt_for(other_admin)}" }
        run_test! do |response|
          expect(response.status).to eq(404)
        end
      end
    end
  end
end
