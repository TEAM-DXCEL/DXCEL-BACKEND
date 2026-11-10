import { handleEvaluation } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve((request) =>
  handleEvaluation(request, async (token, registration) => {
    if (!supabaseUrl || !serviceKey) return { error: "unavailable" };
    const response = await fetch(
      new URL("/rest/v1/rpc/register_ingested_evaluation", supabaseUrl),
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_token: token,
          p_group_id: registration.groupId,
          p_ingestion_id: registration.ingestionId,
          p_repetition: registration.repetition,
          p_attempt: registration.attempt,
          p_generation_id: registration.generationId,
          p_generation_sha256: registration.generationSha256,
          p_previous_run_id: registration.previousRunId,
          p_started_at: registration.startedAt,
          p_finished_at: registration.finishedAt,
          p_metrics: registration.metrics,
        }),
        signal: AbortSignal.timeout(10_000),
      },
    );
    const body = await response.json();
    if (response.ok && typeof body?.run_id === "string" && typeof body?.duplicate === "boolean") {
      return { runId: body.run_id, duplicate: body.duplicate };
    }
    if (body?.code === "28000" || body?.code === "42501") return { error: "unauthorized" };
    if (body?.code === "23505") return { error: "conflict" };
    if (typeof body?.code === "string" && /^(22|23)/.test(body.code)) {
      return { error: "invalid_result" };
    }
    return { error: "unavailable" };
  })
);
