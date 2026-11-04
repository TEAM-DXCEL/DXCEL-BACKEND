import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "dxcel-supabase-test-"));
  const bin = join(root, "bin");
  const originalConfig = join(root, "original");
  mkdirSync(bin);
  mkdirSync(originalConfig);
  writeFileSync(join(originalConfig, "config.json"), '{"credsStore":"desktop"}\n');
  writeFileSync(join(bin, "docker"), '#!/bin/sh\nprintf "unix:///tmp/dxcel-test.sock\\n"\n', {
    mode: 0o755,
  });
  writeFileSync(
    join(bin, "supabase"),
    '#!/bin/sh\nprintf "%s\\n" "$DOCKER_CONFIG" "$DOCKER_HOST" "$*"\ncat "$DOCKER_CONFIG/config.json"\nexit "${TEST_EXIT_CODE:-0}"\n',
    { mode: 0o755 },
  );
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`, DOCKER_CONFIG: originalConfig };
  delete env.DOCKER_HOST;
  return {
    root,
    originalConfig,
    run(overrides = {}) {
      return spawnSync("sh", ["scripts/local-supabase.sh", "start", "--exclude", "vector"], {
        env: { ...env, ...overrides },
        encoding: "utf8",
      });
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    },
  };
}

test("local CLI preserves global credential settings and cleans up isolated configuration", () => {
  const f = fixture();
  try {
    const result = f.run();
    assert.equal(result.status, 0, result.stderr);
    const [isolatedConfig, host, args, config] = result.stdout.trim().split("\n");
    assert.notEqual(isolatedConfig, f.originalConfig);
    assert.equal(host, "unix:///tmp/dxcel-test.sock");
    assert.equal(args, "start --exclude vector");
    assert.deepEqual(JSON.parse(config), { auths: {} });
    assert.equal(existsSync(isolatedConfig), false);
    assert.equal(
      readFileSync(join(f.originalConfig, "config.json"), "utf8"),
      '{"credsStore":"desktop"}\n',
    );
  } finally {
    f.cleanup();
  }
});

test("local CLI refuses a remote Docker daemon", () => {
  const f = fixture();
  try {
    const result = f.run({ DOCKER_HOST: "tcp://remote.example:2375" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /local Docker/);
    assert.equal(result.stdout, "");
  } finally {
    f.cleanup();
  }
});

test("local CLI preserves a failing Supabase exit status and still cleans up", () => {
  const f = fixture();
  try {
    const result = f.run({ TEST_EXIT_CODE: "7" });
    assert.equal(result.status, 7, result.stderr);
    assert.equal(existsSync(result.stdout.split("\n")[0]), false);
  } finally {
    f.cleanup();
  }
});
