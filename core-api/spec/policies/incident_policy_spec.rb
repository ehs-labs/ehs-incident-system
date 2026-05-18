require "rails_helper"

RSpec.describe IncidentPolicy, type: :policy do
  let(:org)          { create(:organization) }
  let(:site)         { create(:site, organization: org) }
  let(:other_org)    { create(:organization) }

  let(:admin)        { create(:user, :admin,        organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:worker)       { create(:user,                organization: org) }
  let(:outsider)     { create(:user, :admin,        organization: other_org) }

  # A fully-populated draft that passes ready_for_submission?.
  let(:draft_incident) do
    create(:incident,
           organization: org,
           site:         site,
           reporter:     worker,
           state:        "draft")
  end

  before do
    create(:site_membership, user: investigator, site: site)
    create(:site_membership, user: admin,        site: site)
  end

  # ---------------------------------------------------------------------------
  # submit?
  # ---------------------------------------------------------------------------
  describe "#submit?" do
    context "when the incident is in draft state" do
      subject(:incident) { draft_incident }

      it "allows a worker who is the reporter" do
        expect(described_class.new(worker, incident).submit?).to be true
      end

      it "allows an investigator who is the reporter" do
        investigator_reporter = create(:user, :investigator, organization: org)
        create(:site_membership, user: investigator_reporter, site: site)
        inc = create(:incident, organization: org, site: site, reporter: investigator_reporter, state: "draft")
        expect(described_class.new(investigator_reporter, inc).submit?).to be true
      end

      it "allows an admin who is the reporter" do
        admin_reporter = create(:user, :admin, organization: org)
        create(:site_membership, user: admin_reporter, site: site)
        inc = create(:incident, organization: org, site: site, reporter: admin_reporter, state: "draft")
        expect(described_class.new(admin_reporter, inc).submit?).to be true
      end

      it "allows an admin who is NOT the reporter" do
        expect(described_class.new(admin, incident).submit?).to be true
      end

      it "denies a worker who is NOT the reporter" do
        other_worker = create(:user, organization: org)
        expect(described_class.new(other_worker, incident).submit?).to be false
      end

      it "denies a user from another org" do
        expect(described_class.new(outsider, incident).submit?).to be false
      end
    end

    context "when the incident is already submitted (may_submit? is false)" do
      let(:submitted_incident) do
        create(:incident, organization: org, site: site, reporter: worker, state: "submitted")
      end

      it "denies the reporter because the AASM guard blocks the transition" do
        expect(described_class.new(worker, submitted_incident).submit?).to be false
      end

      it "denies an admin because the AASM guard blocks the transition" do
        expect(described_class.new(admin, submitted_incident).submit?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # update?
  # ---------------------------------------------------------------------------
  describe "#update?" do
    it "allows an admin regardless of reporter" do
      expect(described_class.new(admin, draft_incident).update?).to be true
    end

    it "allows a site-member investigator" do
      expect(described_class.new(investigator, draft_incident).update?).to be true
    end

    it "allows a worker who is the reporter on a draft" do
      expect(described_class.new(worker, draft_incident).update?).to be true
    end

    it "denies a worker who is not the reporter" do
      other_worker = create(:user, organization: org)
      expect(described_class.new(other_worker, draft_incident).update?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Scope
  # ---------------------------------------------------------------------------
  describe "Scope" do
    before { draft_incident }

    it "admin sees all incidents in their org" do
      other_site = create(:site, organization: org)
      other_reporter = create(:user, organization: org)
      other_inc = create(:incident, organization: org, site: other_site, reporter: other_reporter)

      cross_org_site = create(:site, organization: other_org)
      cross_reporter = create(:user, organization: other_org)
      cross_inc = create(:incident, organization: other_org, site: cross_org_site, reporter: cross_reporter)

      ids = described_class::Scope.new(admin, Incident).resolve.pluck(:id)
      expect(ids).to include(draft_incident.id, other_inc.id)
      expect(ids).not_to include(cross_inc.id)
    end

    it "worker only sees their own incidents" do
      other_reporter = create(:user, organization: org)
      _other_inc = create(:incident, organization: org, site: site, reporter: other_reporter)

      ids = described_class::Scope.new(worker, Incident).resolve.pluck(:id)
      expect(ids).to contain_exactly(draft_incident.id)
    end
  end
end
