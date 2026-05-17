require "rails_helper"

RSpec.describe Incident, "PaperTrail audit trail", versioning: true do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:investigator) { create(:user, :investigator, organization: organization) }

  before do
    create(:site_membership, site: site, user: investigator)
  end

  it "records a version for create" do
    PaperTrail.request.whodunnit = reporter.id.to_s
    incident = create(:incident, organization: organization, site: site, reporter: reporter)

    expect(incident.versions.count).to eq(1)
    expect(incident.versions.last.event).to eq("create")
    expect(incident.versions.last.whodunnit).to eq(reporter.id.to_s)
  end

  it "records a version per AASM state transition with the new state in the changeset" do
    PaperTrail.request.whodunnit = reporter.id.to_s
    incident = create(:incident, organization: organization, site: site, reporter: reporter)
    incident.submit!

    PaperTrail.request.whodunnit = investigator.id.to_s
    incident.update!(assignee: investigator)
    incident.triage!

    PaperTrail.request.whodunnit = investigator.id.to_s
    incident.actions_assigned!
    incident.verify!

    # create + submit + assignee-update + triage + actions_assigned + verify = 6
    expect(incident.versions.count).to eq(6)

    state_diffs = incident.versions.map { |v| v.changeset["state"] }.compact
    expect(state_diffs).to eq([
      %w[draft submitted],
      %w[submitted investigating],
      %w[investigating pending_closure],
      %w[pending_closure closed]
    ])
  end

  it "captures the acting user in whodunnit on each transition" do
    PaperTrail.request.whodunnit = reporter.id.to_s
    incident = create(:incident, organization: organization, site: site, reporter: reporter)
    incident.submit!

    PaperTrail.request.whodunnit = investigator.id.to_s
    incident.update!(assignee: investigator)
    incident.triage!

    last_whodunnits = incident.versions.last(2).map(&:whodunnit)
    expect(last_whodunnits).to all(eq(investigator.id.to_s))
    expect(incident.versions.first.whodunnit).to eq(reporter.id.to_s)
  end
end
