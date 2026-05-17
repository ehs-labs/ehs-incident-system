# ============================================================================
# db/demo_seeds.rb — rich demo data for local development and Playwright e2e.
#
# Idempotent: re-running clears prior demo data and reloads.
# Invoked by: rails db:seed:demo  (defined in lib/tasks/seed_demo.rake)
# ============================================================================

puts "[demo] Clearing existing demo data..."
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
sites     = [sydney, melbourne, perth]

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
worker       = make_user(org: org, email: "worker@acme.demo",       name: "Wendy Worker",      role: :worker,       sites: [sydney])

extra_workers = 4.times.map do |i|
  make_user(org: org,
            email: "worker#{i + 1}@acme.demo",
            name:  ["Ben Worker", "Cara Worker", "Devi Worker", "Eli Worker"][i],
            role:  :worker,
            sites: [sites[i % 3]])
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
  ["closed"] * 14 +
  ["pending_closure"] * 8 +
  ["investigating"] * 8 +
  ["submitted"] * 6 +
  ["draft"] * 4
).shuffle

incidents = state_distribution.each_with_index.map do |target_state, i|
  site     = sites.sample
  reporter = [worker, *extra_workers].sample
  severity = ([1] * 2 + [2] * 4 + [3] * 6 + [4] * 4 + [5] * 4).sample
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
  end
  if target_state == "closed"
    incident.verify!
  end
  Current.user = nil

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
puts "  Outbox events queued: #{OutboxEvent.where(published_at: nil).count}"
