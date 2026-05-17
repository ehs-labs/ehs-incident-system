# Use JSON for object / object_changes so the audit-trail endpoint can hand the
# changeset back to clients without server-side YAML deserialization. The
# default YAML serializer requires `permitted_classes` for TimeWithZone, which
# would couple every reader to that allow-list.
PaperTrail.serializer = PaperTrail::Serializers::JSON
