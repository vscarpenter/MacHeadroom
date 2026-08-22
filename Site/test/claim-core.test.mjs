import assert from "node:assert/strict";
import test from "node:test";

import { handoffOutcome, tokenFromPath } from "../direct/lib/claim-core.mjs";

const TOKEN = "0f1e2d3c-4b5a-4978-8695-a4b3c2d1e0f9";

test("extracts the token from the claim path", () => {
  assert.equal(tokenFromPath(`/direct/claim/${TOKEN}`), TOKEN);
  assert.equal(tokenFromPath(`/direct/claim/${TOKEN}/`), TOKEN);
});

test("rejects paths that do not carry a well-formed token", () => {
  for (const path of [
    "/direct/claim/",
    "/direct/claim/not-a-uuid",
    `/direct/claim/${TOKEN}/extra`,
    `/other/${TOKEN}`,
    `/direct/claim/${TOKEN.toUpperCase()}`,
    "/direct/claim/../../etc/passwd",
  ]) {
    assert.equal(tokenFromPath(path), null, path);
  }
});

test("a valid handoff response becomes a ready outcome", () => {
  const outcome = handoffOutcome(200, {
    downloadURL: "https://releases.example.com/updates/System-Headroom-Direct-1.1.dmg?sig=abc",
    version: "1.1",
    sha256: "a".repeat(64),
  });
  assert.equal(outcome.kind, "ready");
  assert.match(outcome.downloadURL, /^https:\/\//);
  assert.equal(outcome.version, "1.1");
});

test("anything else becomes an expired outcome", () => {
  const cases = [
    [503, { error: "download handoff is unavailable" }],
    [200, null],
    [200, { downloadURL: "http://insecure.example.com/x.dmg", version: "1.1", sha256: "a".repeat(64) }],
    [200, { downloadURL: "https://ok.example.com/x.dmg", version: 7, sha256: "a".repeat(64) }],
    [200, { downloadURL: "https://ok.example.com/x.dmg", version: "1.1" }],
  ];
  for (const [status, payload] of cases) {
    assert.equal(handoffOutcome(status, payload).kind, "expired");
  }
});
