import type { JsonApiResource, JsonApiSingle, JsonApiList } from "@/types/api";

/** Look up an included resource by (type, id). Returns null if not present. */
export function findIncluded<T>(
  doc: JsonApiSingle<unknown> | JsonApiList<unknown>,
  type: string,
  id: string | number | null | undefined
): JsonApiResource<T> | null {
  if (id == null) return null;
  const idStr = String(id);
  return (
    ((doc.included ?? []).find(
      (r) => r.type === type && r.id === idStr
    ) as JsonApiResource<T> | undefined) ?? null
  );
}

/** Flatten a single jsonapi resource into a plain `{ id, ...attributes }` row. */
export function flatten<T>(res: JsonApiResource<T>): T & { id: string } {
  return { id: res.id, ...(res.attributes as T) };
}

export function flattenList<T>(list: JsonApiResource<T>[]): (T & { id: string })[] {
  return list.map(flatten);
}
