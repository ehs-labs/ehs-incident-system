require "rails_helper"

RSpec.describe Comment, type: :model do
  let(:organization) { create(:organization) }
  let(:site)         { create(:site, organization: organization) }
  let(:reporter)     { create(:user, organization: organization) }
  let(:incident)     { create(:incident, organization: organization, site: site, reporter: reporter) }

  describe "associations" do
    it "belongs to an incident and an author" do
      comment = create(:comment, incident: incident, author: reporter)
      expect(comment.incident).to eq(incident)
      expect(comment.author).to eq(reporter)
    end
  end

  describe "validations" do
    it "is valid with a body and author from the same org" do
      expect(build(:comment, incident: incident, author: reporter)).to be_valid
    end

    it "requires a body" do
      comment = build(:comment, incident: incident, author: reporter, body: nil)
      expect(comment).not_to be_valid
      expect(comment.errors[:body]).to be_present
    end

    it "rejects an author from a different organization" do
      other_org   = create(:organization)
      other_user  = create(:user, organization: other_org)
      comment     = build(:comment, incident: incident, author: other_user)

      expect(comment).not_to be_valid
      expect(comment.errors[:author]).to be_present
    end
  end

  describe ".for_org" do
    it "scopes to incidents in the given org" do
      other_org      = create(:organization)
      other_site     = create(:site, organization: other_org)
      other_user     = create(:user, organization: other_org)
      other_incident = create(:incident, organization: other_org, site: other_site, reporter: other_user)

      mine    = create(:comment, incident: incident, author: reporter)
      _theirs = create(:comment, incident: other_incident, author: other_user)

      expect(Comment.for_org(organization)).to contain_exactly(mine)
    end
  end
end
