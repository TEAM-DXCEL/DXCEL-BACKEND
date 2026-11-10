const tokenPattern = /^dxcel_[0-9a-f]{64}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sha256Pattern = /^[0-9a-f]{64}$/;
const timestampPattern = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/;
const maxBodyBytes = 64 * 1024;

type RecordValue = Record<string, unknown>;

type Metric =
  | { metric_id: string; state: "measured"; value: number }
  | { metric_id: string; state: "missing" | "error"; reason: string };

export type EvaluationRegistration = {
  schemaVersion: 1;
  groupId: string;
  ingestionId: string;
  repetition: number;
  attempt: number;
  generationId: string;
  generationSha256: string;
  previousRunId: string | null;
  startedAt: string;
  finishedAt: string;
  metrics: Metric[];
};

export type RegistrationResult =
  | { runId: string; duplicate: boolean }
  | { error: "unauthorized" | "conflict" | "invalid_result" | "unavailable" };

export type RegisterEvaluation = (
  token: string,
  registration: EvaluationRegistration,
) => Promise<RegistrationResult>;

class RequestError extends Error {
  constructor(readonly status: number, readonly code: string) {
    super(code);
  }
}

function object(value: unknown): RecordValue {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new RequestError(400, "invalid_payload");
  }
  return value as RecordValue;
}

function exactKeys(value: RecordValue, keys: readonly string[]) {
  if (Object.keys(value).length !== keys.length || keys.some((key) => !Object.hasOwn(value, key))) {
    throw new RequestError(400, "invalid_payload");
  }
}

function string(value: unknown, pattern: RegExp) {
  if (typeof value !== "string" || !pattern.test(value)) {
    throw new RequestError(400, "invalid_payload");
  }
  return value;
}

function positiveInt(value: unknown) {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1 || value > 2147483647) {
    throw new RequestError(400, "invalid_payload");
  }
  return value;
}

function timestamp(value: unknown) {
  const date = string(value, timestampPattern);
  if (!Number.isFinite(Date.parse(date))) throw new RequestError(400, "invalid_payload");
  return date;
}

function registration(input: unknown): EvaluationRegistration {
  const value = object(input);
  exactKeys(value, [
    "schemaVersion",
    "groupId",
    "ingestionId",
    "repetition",
    "attempt",
    "generationId",
    "generationSha256",
    "previousRunId",
    "startedAt",
    "finishedAt",
    "metrics",
  ]);
  if (
    value.schemaVersion !== 1 || !Array.isArray(value.metrics) || !value.metrics.length ||
    value.metrics.length > 128
  ) {
    throw new RequestError(400, "invalid_payload");
  }
  const metricIds = new Set<string>();
  const metrics = value.metrics.map((item): Metric => {
    const metric = object(item);
    const metric_id = string(metric.metric_id, uuidPattern).toLowerCase();
    if (metricIds.has(metric_id)) throw new RequestError(400, "invalid_payload");
    metricIds.add(metric_id);

    if (metric.state === "measured") {
      exactKeys(metric, ["metric_id", "state", "value"]);
      if (typeof metric.value !== "number" || !Number.isFinite(metric.value)) {
        throw new RequestError(400, "invalid_payload");
      }
      return { metric_id, state: metric.state, value: metric.value };
    }
    if (metric.state !== "missing" && metric.state !== "error") {
      throw new RequestError(400, "invalid_payload");
    }
    exactKeys(metric, ["metric_id", "state", "reason"]);
    const allowedReason = metric.state === "missing"
      ? /^(not_applicable|not_computed|source_missing)$/
      : /^evaluation_failed$/;
    return { metric_id, state: metric.state, reason: string(metric.reason, allowedReason) };
  });
  const startedAt = timestamp(value.startedAt);
  const finishedAt = timestamp(value.finishedAt);
  if (Date.parse(startedAt) > Date.parse(finishedAt)) {
    throw new RequestError(400, "invalid_payload");
  }
  return {
    schemaVersion: 1,
    groupId: string(value.groupId, uuidPattern).toLowerCase(),
    ingestionId: string(value.ingestionId, /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/),
    repetition: positiveInt(value.repetition),
    attempt: positiveInt(value.attempt),
    generationId: string(value.generationId, /^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/),
    generationSha256: string(value.generationSha256, sha256Pattern),
    previousRunId: value.previousRunId === null
      ? null
      : string(value.previousRunId, uuidPattern).toLowerCase(),
    startedAt,
    finishedAt,
    metrics,
  };
}

async function readJson(request: Request): Promise<unknown> {
  if (Number(request.headers.get("content-length")) > maxBodyBytes) {
    throw new RequestError(413, "payload_too_large");
  }
  const reader = request.body?.getReader();
  if (!reader) throw new RequestError(400, "invalid_payload");
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let body = "";
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBodyBytes) throw new RequestError(413, "payload_too_large");
      body += decoder.decode(value, { stream: true });
    }
    return JSON.parse(body + decoder.decode()) as unknown;
  } catch (error) {
    if (error instanceof RequestError) throw error;
    throw new RequestError(400, "invalid_payload");
  } finally {
    void reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function reply(body: RecordValue, status: number, headers?: Record<string, string>) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

const statuses = {
  unauthorized: 401,
  conflict: 409,
  invalid_result: 422,
  unavailable: 503,
} as const;

export async function handleEvaluation(
  request: Request,
  register: RegisterEvaluation,
): Promise<Response> {
  if (request.method !== "POST") {
    return reply({ error: "method_not_allowed" }, 405, { Allow: "POST" });
  }
  const token = request.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token || !tokenPattern.test(token)) return reply({ error: "unauthorized" }, 401);
  if (
    request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() !== "application/json"
  ) {
    return reply({ error: "unsupported_media_type" }, 415);
  }

  try {
    const result = await register(token, registration(await readJson(request)));
    if ("error" in result) return reply({ error: result.error }, statuses[result.error]);
    return reply(
      { runId: result.runId, duplicate: result.duplicate },
      result.duplicate ? 200 : 201,
    );
  } catch (error) {
    if (error instanceof RequestError) return reply({ error: error.code }, error.status);
    return reply({ error: "unavailable" }, 503);
  }
}
