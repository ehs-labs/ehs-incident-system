# =============================================================================
# db:seed:demo — load a rich demo organization, users, sites, incidents,
# corrective actions, and notifications. Used by `bootstrap.sh` and Playwright
# e2e tests.
#
# The actual seed content lives in db/demo_seeds.rb. Until that file exists
# (i.e. while domain models are still being built), this task is a graceful
# no-op so the bootstrap script doesn't fail on an empty project.
# =============================================================================

namespace :db do
  namespace :seed do
    desc "Load rich demo data (db/demo_seeds.rb) for local development and e2e"
    task demo: :environment do
      demo_file = Rails.root.join("db/demo_seeds.rb")

      unless demo_file.exist?
        puts "[db:seed:demo] db/demo_seeds.rb does not exist yet — skipping."
        puts "[db:seed:demo] Create db/demo_seeds.rb to populate demo data."
        next
      end

      if ActiveRecord::Base.connection.tables.empty?
        puts "[db:seed:demo] No tables in the database — run `rails db:migrate` first."
        next
      end

      puts "[db:seed:demo] Loading #{demo_file}..."
      load demo_file.to_s
      puts "[db:seed:demo] Done."
    end
  end
end
