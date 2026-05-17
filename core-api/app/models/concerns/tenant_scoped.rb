module TenantScoped
  extend ActiveSupport::Concern

  # Adds an org_id column lookup via the configured association name (default
  # :organization). Use `scope_for(user)` in Pundit policies to enforce the
  # tenant boundary at query time without relying on `default_scope`.
  class_methods do
    def for_org(org_or_id)
      org_id = org_or_id.is_a?(Organization) ? org_or_id.id : org_or_id
      where(organization_id: org_id)
    end
  end
end
