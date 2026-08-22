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
