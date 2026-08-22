import assert from "node:assert/strict";
import test from "node:test";

process.env.APP_STORE_BUNDLE_ID = "com.vinnycarpenter.MacHeadroom";
process.env.APP_APPLE_ID = "6794655648";

const { parseClaimRequest } = await import("../src/handler.mjs");

test("parses a minimal App Store claim request", () => {
  const request = parseClaimRequest(JSON.stringify({
    appTransactionID: "01234567-transaction-id",
    bundleID: "com.vinnycarpenter.MacHeadroom",
    originalPurchaseDate: "2026-08-13T18:42:00Z",
  }));

  assert.equal(request.appTransactionID, "01234567-transaction-id");
});

test("rejects an untrusted bundle identifier", () => {
  assert.throws(() => parseClaimRequest(JSON.stringify({
    appTransactionID: "01234567-transaction-id",
    bundleID: "com.example.other",
    originalPurchaseDate: "2026-08-13T18:42:00Z",
  })));
});

test("rejects malformed request bodies", () => {
  assert.throws(() => parseClaimRequest("not-json"));
  assert.throws(() => parseClaimRequest(JSON.stringify({})));
});

test("the dark flag gates both routes before any parsing", async () => {
  delete process.env.CLAIM_FLOW_ENABLED;
  const { handler, handoff } = await import("../src/handler.mjs");

  const claimResponse = await handler({ body: "!!definitely-not-json" });
  assert.equal(claimResponse.statusCode, 503);
  assert.deepEqual(JSON.parse(claimResponse.body), { error: "claim flow is not enabled" });

  const handoffResponse = await handoff({ body: "!!definitely-not-json" });
  assert.equal(handoffResponse.statusCode, 503);
  assert.deepEqual(JSON.parse(handoffResponse.body), { error: "claim flow is not enabled" });
});

test("an enabled handoff route rejects malformed bodies with a generic 400", async () => {
  process.env.CLAIM_FLOW_ENABLED = "true";
  try {
    const { handoff } = await import("../src/handler.mjs");
    for (const body of [undefined, "not-json", "x".repeat(2_000), JSON.stringify({})]) {
      const response = await handoff({ body });
      assert.equal(response.statusCode, 400);
      assert.deepEqual(JSON.parse(response.body), { error: "invalid handoff request" });
    }
  } finally {
    delete process.env.CLAIM_FLOW_ENABLED;
  }
});
