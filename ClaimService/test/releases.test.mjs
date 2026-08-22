import assert from "node:assert/strict";
import test from "node:test";

import { DOWNLOAD_URL_TTL_SECONDS, latestRelease } from "../src/releases.mjs";

function fakeS3(manifest) {
  return {
    send: async () => ({
      Body: { transformToString: async () => JSON.stringify(manifest) },
    }),
  };
}

const VALID = {
  version: "1.1",
  build: "12",
  key: "updates/System-Headroom-Direct-1.1.dmg",
  sha256: "a".repeat(64),
};

test("a valid manifest parses", async () => {
  const release = await latestRelease({ client: fakeS3(VALID), bucket: "releases" });
  assert.deepEqual(release, VALID);
});

test("presigned URLs live for fifteen minutes", () => {
  assert.equal(DOWNLOAD_URL_TTL_SECONDS, 900);
});

test("manifests with missing or out-of-prefix keys are rejected", async () => {
  const broken = [
    { ...VALID, key: undefined },
    { ...VALID, key: "elsewhere/app.dmg" },
    { ...VALID, key: "updates/../secrets" },
    { ...VALID, version: undefined },
    { ...VALID, sha256: 42 },
  ];
  for (const manifest of broken) {
    await assert.rejects(() => latestRelease({ client: fakeS3(manifest), bucket: "releases" }));
  }
});
