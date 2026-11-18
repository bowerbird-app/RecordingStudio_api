# Idempotency keys

Built-in create stores the first successful response for 24 hours. The storage key is `{namespace}:idempotency:{api}:{client id}:{digest of the Idempotency-Key}`. One API client cannot read another client's entry. A named API cannot read the public API's entry.

Redis stores the entry when it is reachable (`SET NX`). When Redis is missing or raises `Redis::BaseError`, the store uses `Rails.cache` with `unless_exist`. `MemoryStore` and `NullStore` log one warning because they are process-local. `NullStore` stores nothing, so it cannot replay.

## Fingerprint

`RecordingStudioApi::IdempotencyStore.fingerprint(method:, path:, params:)` returns a SHA256 hex digest.

- `method` is the HTTP method. `post` and `POST` are the same fingerprint.
- `path` is the request path or the resource type. Built-in create uses the resource name. A nested create also includes the parent recording id (`folders/<parent id>`).
- `params` is the request body. Hash keys are sorted at every level. Array order is kept. Symbol keys and string keys match. Header values are not included.

The same inputs always return the same digest.

## Fetch and write

```ruby
fingerprint = RecordingStudioApi::IdempotencyStore.fingerprint(
  method: "POST",
  path: "folders",
  params: { "name" => "Notes", "parent_id" => parent_id }
)

stored = RecordingStudioApi::IdempotencyStore.fetch(
  api: "public",
  client_id: client_id,
  key: idempotency_key,
  fingerprint: fingerprint
)

RecordingStudioApi::IdempotencyStore.write(
  api: "public",
  client_id: client_id,
  key: idempotency_key,
  payload: response_json,
  status: "created",
  fingerprint: fingerprint
)
```

`fetch` returns the stored hash (`json`, `status`, and `fingerprint` when one was stored), or `nil` when nothing is stored.

`fingerprint:` is optional. Omit it and `fetch` returns the stored response without comparing fingerprints. Pass it and a stored fingerprint that differs raises `RecordingStudioApi::IdempotencyKeyMismatchError`.

A stored entry with no `fingerprint` still replays. Create entries written before 1.19.0 are in that shape until their 24 hours end.

`write` keeps the first value for the key. A later write does not replace it.

## Mismatch

`RecordingStudioApi::IdempotencyKeyMismatchError` is a `RecordingStudioApi::Error`.

- `code` is `idempotency_key_reused`.
- `message` is `Idempotency key already used with different parameters`.

Built-in HTTP create rescues it and responds 422:

```json
{
  "error": {
    "code": "idempotency_key_reused",
    "message": "Idempotency key already used with different parameters"
  }
}
```

The create does not run. Another gem rescues `RecordingStudioApi::IdempotencyKeyMismatchError` and passes `code` and `message` through in that same shape.

## Replay

`RecordingStudioApi::Idempotency.replay` is the shared entry. It calls `IdempotencyStore.fetch` and `write`.

Built-in create passes `fingerprint:` from `IdempotencyStore.fingerprint`. The same key and fingerprint return the stored response. A different fingerprint raises `IdempotencyKeyMismatchError` before the record is created.

A capability action with `creates: true` passes `input:`. `replay` hashes that input and passes the digest as `fingerprint:` to the store. The same key and input replay. A different input raises `IdempotencyKeyMismatchError`. Pass an explicit `fingerprint:` when the digest should be the method, path, and body helper instead of the input hash.

A `register_resource_handler` for `create` calls `replay` without `input` or `fingerprint`. A different body still returns the first stored response.
