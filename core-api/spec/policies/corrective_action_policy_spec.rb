require "rails_helper"

RSpec.describe CorrectiveActionPolicy, type: :policy do
  let(:org)          { create(:organization) }
  let(:site_a)       { create(:site, organization: org) }
  let(:site_b)       { create(:site, organization: org) }
  let(:other_org)    { create(:organization) }

  let(:admin)        { create(:user, :admin,        organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:worker)       { create(:user,                organization: org) }
  let(:other_user)   { create(:user,                organization: org) }
  let(:outsider)     { create(:user,                organization: other_org) }

  let(:incident) do
    create(:incident, organization: org, site: site_a, reporter: worker)
  end

  let(:action) do
    create(:corrective_action, incident: incident, assignee: worker,
                               created_by: investigator)
  end

  before do
    # Investigator is a member of site_a (covers the incident's site).
    create(:site_membership, user: investigator, site: site_a)
  end

  describe "#create?" do
    it "permits admin and site-member investigator" do
      expect(described_class.new(admin,        action).create?).to be true
      expect(described_class.new(investigator, action).create?).to be true
    end

    it "denies workers and non-member investigators" do
      stranger_investigator = create(:user, :investigator, organization: org)
      expect(described_class.new(worker,                action).create?).to be false
      expect(described_class.new(stranger_investigator, action).create?).to be false
    end

    it "denies users from another org" do
      expect(described_class.new(outsider, action).create?).to be false
    end
  end

  describe "#update?" do
    it "permits admin, site-member investigator, and the assignee" do
      expect(described_class.new(admin,        action).update?).to be true
      expect(described_class.new(investigator, action).update?).to be true
      expect(described_class.new(worker,       action).update?).to be true # assignee
    end

    it "denies a worker who is neither assignee nor reporter" do
      expect(described_class.new(other_user, action).update?).to be false
    end
  end

  describe "transition guards" do
    around(:each) do |ex|
      Current.user = worker
      ex.run
    ensure
      Current.user = nil
    end

    it "only the assignee can :start and :complete" do
      expect(described_class.new(worker,       action).start?).to be true
      action.start!
      expect(described_class.new(worker,       action).complete?).to be true

      expect(described_class.new(investigator, action).start?).to be false
      expect(described_class.new(admin,        action).complete?).to be false
    end

    it "only admin/site investigator can :verify" do
      action.start!; action.complete!
      expect(described_class.new(investigator, action).verify?).to be true
      expect(described_class.new(admin,        action).verify?).to be true
      expect(described_class.new(worker,       action).verify?).to be false
    end

    it "only admin/site investigator can :cancel" do
      expect(described_class.new(investigator, action).cancel?).to be true
      expect(described_class.new(admin,        action).cancel?).to be true
      expect(described_class.new(worker,       action).cancel?).to be false
    end
  end

  describe "Scope" do
    before do
      # action — site_a, assignee=worker, reporter=worker
      action
      # Another action on a site_b incident, assigned to other_user.
      site_b_incident = create(:incident, organization: org, site: site_b, reporter: other_user)
      @other_action = create(:corrective_action,
                             incident: site_b_incident,
                             assignee: other_user,
                             created_by: investigator)
      # And one in another organization entirely.
      other_org_site = create(:site, organization: other_org)
      other_org_user = create(:user,  organization: other_org)
      other_org_incident = create(:incident, organization: other_org, site: other_org_site, reporter: other_org_user)
      @cross_org_action = create(:corrective_action,
                                 incident: other_org_incident,
                                 assignee: other_org_user,
                                 created_by: other_org_user)
    end

    it "admin sees every action in their org" do
      ids = CorrectiveActionPolicy::Scope.new(admin, CorrectiveAction).resolve.pluck(:id)
      expect(ids).to include(action.id, @other_action.id)
      expect(ids).not_to include(@cross_org_action.id)
    end

    it "investigator sees only actions on incidents at sites they belong to" do
      ids = CorrectiveActionPolicy::Scope.new(investigator, CorrectiveAction).resolve.pluck(:id)
      expect(ids).to include(action.id)
      expect(ids).not_to include(@other_action.id, @cross_org_action.id)
    end

    it "worker sees actions where they are assignee or where they reported the parent incident" do
      ids = CorrectiveActionPolicy::Scope.new(worker, CorrectiveAction).resolve.pluck(:id)
      expect(ids).to include(action.id)
      expect(ids).not_to include(@other_action.id, @cross_org_action.id)
    end
  end
end
