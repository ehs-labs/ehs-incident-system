require "rails_helper"

RSpec.describe CorrectiveAction, type: :model do
  let(:org)          { create(:organization) }
  let(:site)         { create(:site, organization: org) }
  let(:reporter)     { create(:user, organization: org) }
  let(:investigator) { create(:user, :investigator, organization: org) }
  let(:assignee)     { create(:user, organization: org) }

  # Build an incident already at :pending_closure (so verify can transition
  # it to :closed when all corrective actions are verified).
  def pending_closure_incident
    incident = create(:incident, organization: org, site: site, reporter: reporter)
    Current.user = reporter
    incident.submit!
    incident.assignee = investigator
    incident.save!
    Current.user = investigator
    incident.triage!
    incident.actions_assigned!
    incident.reload
  end

  describe "validations" do
    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }

    it "requires a title" do
      action = build(:corrective_action, incident: incident, assignee: assignee, created_by: investigator, title: nil)
      expect(action).not_to be_valid
      expect(action.errors[:title]).to include("can't be blank")
    end

    it "rejects a due_date in the past on create" do
      action = build(:corrective_action, incident: incident, assignee: assignee, created_by: investigator, due_date: 1.day.ago)
      expect(action).not_to be_valid
      expect(action.errors[:due_date]).to include("must be in the future")
    end

    it "rejects an assignee from another organization" do
      other_org   = create(:organization)
      outside_user = create(:user, organization: other_org)
      action = build(:corrective_action, incident: incident, assignee: outside_user, created_by: investigator)
      expect(action).not_to be_valid
      expect(action.errors[:assignee].first).to match(/same organization/)
    end
  end

  describe "AASM transitions" do
    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }
    let(:action)   { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }

    around(:each) do |ex|
      Current.user = investigator
      ex.run
    ensure
      Current.user = nil
    end

    it "starts in :open" do
      expect(action.state).to eq("open")
    end

    it "open -> in_progress via :start" do
      expect { action.start! }.to change(action, :state).from("open").to("in_progress")
    end

    it "in_progress -> done via :complete (sets completed_at)" do
      action.start!
      expect { action.complete! }.to change(action, :state).to("done")
      expect(action.reload.completed_at).to be_within(5.seconds).of(Time.current)
    end

    it "done -> verified via :verify (sets verified_at)" do
      action.start!
      action.complete!
      expect { action.verify! }.to change(action, :state).to("verified")
      expect(action.reload.verified_at).to be_within(5.seconds).of(Time.current)
    end

    it "cancel works from open / in_progress / done" do
      a1 = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      a2 = create(:corrective_action, :in_progress, incident: incident, assignee: assignee, created_by: investigator)
      a3 = create(:corrective_action, :done, incident: incident, assignee: assignee, created_by: investigator)

      expect { a1.cancel! }.to change(a1, :state).to("cancelled")
      expect { a2.cancel! }.to change(a2, :state).to("cancelled")
      expect { a3.cancel! }.to change(a3, :state).to("cancelled")
    end
  end

  describe "incident auto-close on verify" do
    around(:each) do |ex|
      Current.user = investigator
      ex.run
    ensure
      Current.user = nil
    end

    it "transitions the parent incident to :closed once all corrective actions are verified" do
      incident = pending_closure_incident
      a1 = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      a2 = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)

      a1.start!; a1.complete!; a1.verify!
      expect(incident.reload.state).to eq("pending_closure")

      a2.start!; a2.complete!; a2.verify!
      expect(incident.reload.state).to eq("closed")
    end

    it "ignores cancelled siblings when deciding whether to close" do
      incident = pending_closure_incident
      a1 = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      a2 = create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator)
      a2.cancel!

      a1.start!; a1.complete!; a1.verify!
      expect(incident.reload.state).to eq("closed")
    end
  end

  describe "#overdue?" do
    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }

    it "is true when due_date is past and state is open" do
      action = create(:corrective_action, :overdue, incident: incident, assignee: assignee, created_by: investigator)
      expect(action).to be_overdue
    end

    it "is false when state is verified" do
      action = create(:corrective_action, :overdue, incident: incident, assignee: assignee, created_by: investigator)
      action.update_column(:state, "verified")
      expect(action.reload).not_to be_overdue
    end
  end

  describe "event publishing" do
    let(:incident) { create(:incident, organization: org, site: site, reporter: reporter) }
    let(:action)   { create(:corrective_action, incident: incident, assignee: assignee, created_by: investigator) }

    it "writes a CorrectiveActionAssigned outbox event with the right subject" do
      action # force-create before counting
      expect { action.publish_assigned_event! }
        .to change { OutboxEvent.where(event_type: "CorrectiveActionAssigned").count }.by(1)

      event = OutboxEvent.where(event_type: "CorrectiveActionAssigned").order(:id).last
      expect(event.event_type).to eq("CorrectiveActionAssigned")
      expect(event.topic).to eq("corrective_actions.v1")
      expect(event.partition_key).to eq(org.id.to_s)

      subject = event.payload["subject"]
      expect(subject.keys).to match_array(%w[action_id incident_id assignee_id title due_date note])
      expect(subject["action_id"]).to eq(action.id.to_s)
      expect(subject["incident_id"]).to eq(incident.id.to_s)
      expect(subject["assignee_id"]).to eq(assignee.id.to_s)
    end

    it "writes a CorrectiveActionCompleted outbox event when transitioning to :done" do
      incident.update_column(:assignee_id, investigator.id)
      Current.user = assignee
      action.start!

      expect { action.complete! }
        .to change { OutboxEvent.where(event_type: "CorrectiveActionCompleted").count }.by(1)

      event = OutboxEvent.where(event_type: "CorrectiveActionCompleted").order(:id).last
      expect(event.topic).to eq("corrective_actions.v1")
      expect(event.partition_key).to eq(org.id.to_s)
      expect(event.payload["actor_id"]).to eq(assignee.id.to_s)
      expect(event.payload["recipient_user_ids"]).to match_array([ investigator.id.to_s ])

      subject = event.payload["subject"]
      expect(subject.keys).to match_array(%w[action_id incident_id assignee_id title completed_at note])
      expect(subject["action_id"]).to eq(action.id.to_s)
      expect(subject["incident_id"]).to eq(incident.id.to_s)
      expect(subject["assignee_id"]).to eq(assignee.id.to_s)
    ensure
      Current.user = nil
    end

    it "writes a CorrectiveActionOverdue outbox event with days_overdue" do
      action.update_column(:due_date, 3.days.ago)

      expect { action.publish_overdue_event! }.to change(OutboxEvent, :count).by(1)

      event = OutboxEvent.order(:id).last
      expect(event.event_type).to eq("CorrectiveActionOverdue")
      expect(event.payload["actor_id"]).to eq("system")
      expect(event.payload["subject"]["days_overdue"]).to be >= 3
      expect(event.payload["recipient_user_ids"]).to include(assignee.id.to_s, reporter.id.to_s)
    end

    it "logs a CorrectiveActionEvent row on every transition with the right actor and note" do
      incident.update_column(:assignee_id, investigator.id)

      Current.user = assignee
      action.pending_note = "Begin today after parts arrive"
      action.start!

      action.pending_note = "Replaced wheel, bearing looks worn"
      action.complete!

      Current.user = investigator
      action.pending_note = "Confirmed; signing off"
      action.verify!

      events = action.events.order(:created_at)
      expect(events.map(&:event_name)).to eq(%w[started completed verified])
      expect(events.map(&:actor_id)).to eq([ assignee.id, assignee.id, investigator.id ])
      expect(events.map(&:note)).to eq([
        "Begin today after parts arrive",
        "Replaced wheel, bearing looks worn",
        "Confirmed; signing off"
      ])
    ensure
      Current.user = nil
    end

    it "writes a nil-note event row when no pending_note is set" do
      Current.user = assignee
      action.start!
      action.complete!

      expect(action.events.last.note).to be_nil
    ensure
      Current.user = nil
    end

    it "includes the note in the CorrectiveActionCompleted outbox payload" do
      incident.update_column(:assignee_id, investigator.id)
      Current.user = assignee
      action.start!
      action.pending_note = "Replaced wheel"
      action.complete!

      event = OutboxEvent.where(event_type: "CorrectiveActionCompleted").order(:id).last
      expect(event.payload["subject"]["note"]).to eq("Replaced wheel")
    ensure
      Current.user = nil
    end
  end
end
