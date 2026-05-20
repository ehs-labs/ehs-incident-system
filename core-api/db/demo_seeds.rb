# ============================================================================
# db/demo_seeds.rb — rich demo data for local development and Playwright e2e.
#
# Idempotent: re-running clears prior demo data and reloads.
# Invoked by: rails db:seed:demo  (defined in lib/tasks/seed_demo.rake)
# ============================================================================

puts "[demo] Clearing existing demo data..."
CorrectiveAction.destroy_all if defined?(CorrectiveAction)
Comment.destroy_all
Witness.destroy_all
Incident.destroy_all
SiteMembership.destroy_all
User.destroy_all
Site.destroy_all
Organization.where(slug: "acme-manufacturing").destroy_all

puts "[demo] Creating org + sites..."
org = Organization.create!(name: "Acme Manufacturing", slug: "acme-manufacturing")
sydney    = Site.create!(organization: org, name: "Sydney Warehouse",    timezone: "Australia/Sydney")
melbourne = Site.create!(organization: org, name: "Melbourne Plant",     timezone: "Australia/Melbourne")
perth     = Site.create!(organization: org, name: "Perth Distribution",  timezone: "Australia/Perth")
sites     = [ sydney, melbourne, perth ]

puts "[demo] Creating users..."
def make_user(org:, email:, name:, role:, sites:)
  user = User.create!(
    organization: org,
    email:        email,
    password:     "password",
    password_confirmation: "password",
    name:         name,
    role:         role,
    confirmed_at: Time.current   # bypass email confirmation for demo accounts
  )
  Array(sites).each { |s| SiteMembership.create!(user: user, site: s) }
  user
end

admin        = make_user(org: org, email: "admin@acme.demo",        name: "Alex Admin",        role: :admin,        sites: sites)
investigator = make_user(org: org, email: "investigator@acme.demo", name: "Pat Investigator", role: :investigator, sites: sites)
worker       = make_user(org: org, email: "worker@acme.demo",       name: "Wendy Worker",      role: :worker,       sites: [ sydney ])

extra_workers = 4.times.map do |i|
  make_user(org: org,
            email: "worker#{i + 1}@acme.demo",
            name:  [ "Ben Worker", "Cara Worker", "Devi Worker", "Eli Worker" ][i],
            role:  :worker,
            sites: [ sites[i % 3] ])
end

puts "[demo] Creating incidents across states + severities..."

INCIDENT_TYPES   = %w[collision slip fall near_miss exposure mechanical electrical fire other].freeze
SAMPLE_SUMMARIES = [
  "Forklift collision in aisle 4",
  "Trip on cable in packaging zone",
  "Hot pipe contact while changing valve",
  "Near-miss with overhead crane",
  "Chemical spill at decanting station",
  "Sprained ankle on uneven floor",
  "Smoke alarm activation in switchgear room",
  "Pallet jack tipping incident"
].freeze

rand_in = ->(range) { rand(range) }

# Most incidents are closed, then pending_closure, then investigating, then submitted, with a few drafts
state_distribution = (
  [ "closed" ] * 14 +
  [ "pending_closure" ] * 8 +
  [ "investigating" ] * 8 +
  [ "submitted" ] * 6 +
  [ "draft" ] * 4
).shuffle

incidents = state_distribution.each_with_index.map do |target_state, i|
  site     = sites.sample
  reporter = [ worker, *extra_workers ].sample
  severity = ([ 1 ] * 2 + [ 2 ] * 4 + [ 3 ] * 6 + [ 4 ] * 4 + [ 5 ] * 4).sample
  occurred = rand(2.weeks.to_i).seconds.ago

  incident = Incident.create!(
    organization: org,
    site:         site,
    reporter:     reporter,
    incident_type: INCIDENT_TYPES.sample,
    severity:     severity,
    occurred_at:  occurred,
    location:     "Aisle #{rand(1..12)}, Bay #{rand(1..8)}",
    summary:      SAMPLE_SUMMARIES.sample,
    description:  "Reporter observed event around #{occurred.strftime('%H:%M')}. Immediate area was secured.",
    state:        "draft"
  )

  # Walk the state machine until we reach target_state
  Current.user = reporter
  if %w[submitted investigating pending_closure closed].include?(target_state)
    incident.submit!
  end
  if %w[investigating pending_closure closed].include?(target_state)
    Current.user = investigator
    incident.assignee = investigator
    incident.save!
    incident.triage!
  end
  if %w[pending_closure closed].include?(target_state)
    incident.update!(root_cause: "Root cause: contributing factors include environmental conditions and procedural compliance.")
    incident.actions_assigned!

    # 1-2 corrective actions per incident at this stage.
    Current.user = investigator
    rand(1..2).times do |a_idx|
      assignee_user = [ investigator, *extra_workers ].sample
      # Mix of past + future due dates so the overdue scanner has work to do.
      due = (rand(-5..10).days.from_now)
      action = CorrectiveAction.new(
        incident:    incident,
        assignee:    assignee_user,
        created_by:  investigator,
        title:       "Action #{a_idx + 1}: #{[ 'Inspect equipment', 'Retrain staff', 'Update SOP', 'Replace part' ].sample}",
        description: "Follow-up action arising from incident investigation.",
        due_date:    due > Time.current ? due : 1.day.from_now
      )
      action.save!
      # Backdate due_date for "overdue" candidates to bypass the create-time
      # future-only validation.
      action.update_column(:due_date, due) if due <= Time.current

      # Walk action state for "closed" incidents so the parent stays closed.
      if target_state == "closed"
        action.start!
        action.complete!
        action.verify!
      elsif rand < 0.3
        action.start!
        action.complete! if rand < 0.4
      end
    end
  end
  if target_state == "closed"
    # Incident reaches "closed" automatically via CorrectiveAction#verify!
    # callback once all actions are verified; only call verify! here if not
    # already in :closed (edge case: zero actions slipped through).
    incident.reload
    incident.verify! if incident.may_verify?
  end
  Current.user = nil

  # Witnesses + comments + attachments for incidents at submitted+ states.
  if %w[submitted investigating pending_closure closed].include?(target_state)
    rand(0..2).times do
      Witness.create!(
        incident: incident,
        name:     Faker::Name.name,
        email:    (Faker::Internet.email if rand < 0.7),
        phone:    (Faker::PhoneNumber.cell_phone if rand < 0.5),
        statement: Faker::Lorem.paragraph(sentence_count: rand(1..4))
      )
    end

    rand(0..3).times do
      author = [ reporter, investigator, admin ].sample
      Comment.create!(
        incident: incident,
        author:   author,
        body:     Faker::Lorem.paragraph(sentence_count: rand(1..3))
      )
    end

    rand(0..2).times do
      png_bytes = StringIO.new(
        "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01" \
        "\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0dIDAT" \
        "\x78\x9cc\xf8\xff\xff?\x03\x00\x05\xfe\x02\xfe\xa3\x35\x81\x84" \
        "\x00\x00\x00\x00IEND\xaeB`\x82".dup.force_encoding("ASCII-8BIT")
      )
      incident.photos.attach(
        io:           png_bytes,
        filename:     "demo-#{SecureRandom.hex(4)}.png",
        content_type: "image/png"
      )
    end
  end

  print "."
  incident
end

puts
puts "[demo] Done."
puts ""
puts "Demo accounts (password: password):"
puts "  admin@acme.demo         (Admin, all 3 sites)"
puts "  investigator@acme.demo  (Investigator, all 3 sites)"
puts "  worker@acme.demo        (Worker, Sydney)"
puts "  worker1@acme.demo .. worker4@acme.demo (Workers, varied sites)"
puts ""
puts "Stats:"
puts "  Organization: #{org.name} (slug: #{org.slug})"
puts "  Sites:        #{sites.size}"
puts "  Users:        #{User.where(organization: org).count}"
puts "  Incidents:    #{Incident.where(organization: org).count}"
puts "    by state: #{Incident.where(organization: org).group(:state).count}"
puts "  Corrective actions: #{CorrectiveAction.joins(:incident).where(incidents: { organization_id: org.id }).count}"
puts "    by state: #{CorrectiveAction.joins(:incident).where(incidents: { organization_id: org.id }).group(:state).count}"
puts "  Outbox events queued: #{OutboxEvent.where(published_at: nil).count}"
