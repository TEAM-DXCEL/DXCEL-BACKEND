import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const database = `dxcel_verify_${randomUUID().replaceAll("-", "")}`;

function sql(query, db = database) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "psql",
      [
        "-X",
        "-qAt",
        "-v",
        "ON_ERROR_STOP=1",
        "-v",
        "VERBOSITY=verbose",
        "-h",
        "127.0.0.1",
        "-p",
        "54322",
        "-U",
        "postgres",
        "-d",
        db,
      ],
      {
        cwd: root,
        env: {
          ...process.env,
          PGPASSWORD: "postgres",
          PGOPTIONS: "-c statement_timeout=30000 -c lock_timeout=10000",
        },
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => {
      stdout += data;
    });
    child.stderr.on("data", (data) => {
      stderr += data;
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.stdin.on("error", () => {});
    child.stdin.end(query);
  });
}
async function must(query, db) {
  const result = await sql(query, db);
  assert.equal(result.code, 0, result.stderr);
  return result.stdout.trim();
}
const actor = "00000000-0000-0000-0000-000000000021";
const other = "00000000-0000-0000-0000-000000000022";
const session = (id = actor) =>
  `set local role authenticated; select set_config('request.jwt.claim.sub', '${id}', true);`;

try {
  await must(`create database ${database};`, "postgres");
  await must(`
    create schema auth;
    create schema extensions;
    create table auth.users(id uuid primary key, email text);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
    $$;
    grant usage on schema auth, extensions to authenticated, anon;
    create extension pgtap with schema extensions;
  `);
  const migrations = (await readdir(`${root}/supabase/migrations`))
    .filter((name) => name.endsWith(".sql"))
    .sort();
  for (const name of migrations) {
    await must(`begin;\n${await readFile(`${root}/supabase/migrations/${name}`, "utf8")}\ncommit;`);
  }
  console.log(`Fresh database: ${migrations.length} migrations applied in order.`);
  for (const name of (await readdir(`${root}/supabase/tests/database`))
    .filter((name) => name.endsWith(".sql"))
    .sort()) {
    const output = await must(await readFile(`${root}/supabase/tests/database/${name}`, "utf8"));
    assert.doesNotMatch(output, /^not ok|^# Looks like you failed/m, output);
    assert.match(output, /^1\.\.\d+$/m, "Missing pgTAP completion plan");
    console.log(`Fresh database: ${name} passed.`);
  }
  const fixture = JSON.parse(
    (
      await must(`
    insert into auth.users(id, email) values ('${actor}', 'race-a@example.invalid'), ('${other}', 'race-b@example.invalid');
    begin;
    ${session()}
    do $$ declare p uuid; e uuid; r uuid; m uuid; c uuid; g uuid; n uuid; begin
      p := public.create_project('Concurrency fixture');
      perform public.set_project_member(p, '${other}', 'owner');
      e := public.create_experiment(p, 1, 'Experiment', 'H', 'C', 'R', 'P');
      select current_revision_id into r from public.experiments where id = e;
      m := public.define_metric(p, 'Metric', 1, 'ratio', 'higher');
      c := public.create_comparison_context(p, 'Context', 'dataset', 'split', 'eval', 10, jsonb_build_array(jsonb_build_object('metric_id', m)));
      g := public.create_run_group(p, e, r, c, 1);
      n := public.create_note(p, 'Body', 'Initial', e);
      perform set_config('dxcel.fixture', jsonb_build_object('project', p, 'experiment', e, 'metric', m, 'group', g, 'note', n)::text, true);
    end $$;
    select current_setting('dxcel.fixture');
    commit;
  `)
    )
      .split("\n")
      .at(-1),
  );
  const runCall = `select public.record_run('${fixture.project}', '${fixture.group}', 'race-registration', 1, 1, 'succeeded', 'race-output', '[{"metric_id":"${fixture.metric}","state":"measured","value":0.5}]');`;
  const race = (call, id = actor) =>
    sql(`begin; ${session(id)} ${call} select pg_sleep(0.2); commit;`);
  const registrations = await Promise.all([race(runCall), race(runCall)]);
  assert.ok(
    registrations.every((result) => result.code === 0),
    JSON.stringify(registrations),
  );
  assert.equal(
    await must("select count(*) from public.runs where ingestion_id = 'race-registration';"),
    "1",
  );
  console.log("Concurrent identical ingestion: one result retained, both requests succeeded.");
  const edits = await Promise.all([
    race(
      `select public.revise_experiment('${fixture.project}', '${fixture.experiment}', 1, 'H2', 'C2', 'R2', 'P2');`,
    ),
    race(
      `select public.revise_experiment('${fixture.project}', '${fixture.experiment}', 1, 'H3', 'C3', 'R3', 'P3');`,
    ),
  ]);
  assert.equal(edits.filter((result) => result.code === 0).length, 1);
  assert.ok(edits.some((result) => result.stderr.includes("40001")));
  console.log("Concurrent design edits: one revision appended, stale writer rejected.");
  const notes = await Promise.all([
    race(
      `select public.revise_note('${fixture.project}', '${fixture.note}', 1, 'Edit A', 'Reason');`,
    ),
    race(
      `select public.revise_note('${fixture.project}', '${fixture.note}', 1, 'Edit B', 'Reason');`,
    ),
  ]);
  assert.equal(notes.filter((result) => result.code === 0).length, 1);
  assert.ok(notes.some((result) => result.stderr.includes("40001")));
  console.log("Concurrent note edits: one revision appended, stale writer rejected.");
  const owners = await Promise.all([
    race(`select public.set_project_member('${fixture.project}', '${actor}', 'viewer');`),
    race(`select public.set_project_member('${fixture.project}', '${other}', 'viewer');`, other),
  ]);
  assert.equal(owners.filter((result) => result.code === 0).length, 1);
  assert.ok(owners.some((result) => result.stderr.includes("23514")));
  assert.equal(
    await must(
      `select count(*) from public.project_members where project_id = '${fixture.project}' and role = 'owner';`,
    ),
    "1",
  );
  console.log("Concurrent owner demotions: last owner retained.");
} finally {
  const cleanup = await sql(`drop database if exists ${database} with (force);`, "postgres");
  assert.equal(cleanup.code, 0, cleanup.stderr);
}
