import assert from "node:assert/strict";
import { handleEvaluation, type RegisterEvaluation } from "./handler.ts";

const token = `dxcel_${"a".repeat(64)}`;
const groupId = "00000000-0000-0000-0000-000000000041";
const metricId = "00000000-0000-0000-0000-000000000042";
const runId = "00000000-0000-0000-0000-000000000043";
const payload = {
  schemaVersion: 1,
  groupId,
  ingestionId: "evaluation-1",
  repetition: 1,
  attempt: 1,
  generationId: "generation-1",
  generationSha256: "b".repeat(64),
  previousRunId: null,
  startedAt: "2026-11-10T00:00:00Z",
  finishedAt: "2026-11-10T00:01:00Z",
  metrics: [{ metric_id: metricId, state: "measured", value: 0 }],
};

function request(body: unknown, authorization = `Bearer ${token}`) {
  return new Request("http://localhost/register-evaluation", {
    method: "POST",
    headers: { Authorization: authorization, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const unexpected: RegisterEvaluation = () => {
  throw new Error("Invalid request reached the registration callback");
};

Deno.test("returns created and duplicate status with the same run ID", async () => {
  for (const duplicate of [false, true]) {
    const response = await handleEvaluation(request(payload), (providedToken, result) => {
      assert.equal(providedToken, token);
      assert.deepEqual(result, payload);
      return Promise.resolve({ runId, duplicate });
    });
    assert.equal(response.status, duplicate ? 200 : 201);
    assert.deepEqual(await response.json(), { runId, duplicate });
  }
});

Deno.test("rejects requests without a correctly formatted registration token", async () => {
  const response = await handleEvaluation(request(payload, "Bearer invalid"), unexpected);
  assert.equal(response.status, 401);
});

Deno.test("rejects unknown fields, duplicate metrics, and non-catalogued missing reasons", async () => {
  const invalid = [
    { ...payload, artifactPath: "/private/artifact.csv" },
    { ...payload, metrics: [...payload.metrics, ...payload.metrics] },
    { ...payload, metrics: [{ metric_id: metricId, state: "missing", reason: "internal path" }] },
  ];
  for (const body of invalid) {
    const response = await handleEvaluation(request(body), unexpected);
    assert.equal(response.status, 400);
  }
});

Deno.test("rejects oversized request bodies without registering them", async () => {
  const response = await handleEvaluation(request("x".repeat(65537)), unexpected);
  assert.equal(response.status, 413);
});

Deno.test("maps conflict and database errors to safe HTTP responses", async () => {
  const conflicts = await handleEvaluation(
    request(payload),
    () => Promise.resolve({ error: "conflict" }),
  );
  assert.equal(conflicts.status, 409);
  const failed = await handleEvaluation(request(payload), unexpected);
  assert.equal(failed.status, 503);
  assert.deepEqual(await failed.json(), { error: "unavailable" });
});
