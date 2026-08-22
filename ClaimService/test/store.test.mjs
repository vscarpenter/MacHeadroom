import assert from "node:assert/strict";
import test from "node:test";

import { GetCommand, PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";

import {
  CLAIM_TTL_SECONDS,
  DOWNLOADS_PER_HANDOFF,
  HANDOFF_TTL_SECONDS,
  REISSUE_LIMIT,
  REISSUE_WINDOW_SECONDS,
  consumeHandoff,
  recordClaim,
} from "../src/store.mjs";

const TABLE = "claims-test";
const NOW = 1_766_000_000;
const HASH = "hash-of-transaction";
const UUID = "0f1e2d3c-4b5a-4978-8695-a4b3c2d1e0f9";

function fakeStore(handlers) {
  const sent = [];
  return {
    sent,
    send: async (command) => {
      sent.push(command);
      const handler = handlers[command.constructor.name];
      if (!handler) {
        throw new Error(`unexpected command ${command.constructor.name}`);
      }
      return handler(command.input);
    },
  };
}

test("first claim writes a fresh record and a handoff token", async () => {
  const store = fakeStore({
    GetCommand: () => ({}),
    PutCommand: () => ({}),
  });

  const claimID = await recordClaim({
    store,
    tableName: TABLE,
    transactionHash: HASH,
    originalPurchaseDate: "2026-08-13T18:42:00Z",
    now: NOW,
    newClaimID: () => UUID,
  });

  assert.equal(claimID, UUID);
  const puts = store.sent.filter((command) => command instanceof PutCommand);
  assert.equal(puts.length, 2);

  const claimItem = puts[0].input.Item;
  assert.equal(claimItem.transactionHash, HASH);
  assert.equal(claimItem.claimID, UUID);
  assert.equal(claimItem.status, "active");
  assert.equal(claimItem.reissueCount, 0);
  assert.equal(claimItem.reissueWindowStart, NOW);
  assert.equal(claimItem.expiresAt, NOW + CLAIM_TTL_SECONDS);
  assert.equal(puts[0].input.ConditionExpression, "attribute_not_exists(transactionHash)");

  const handoffItem = puts[1].input.Item;
  assert.equal(handoffItem.transactionHash, `handoff#${UUID}`);
  assert.equal(handoffItem.claimTransactionHash, HASH);
  assert.equal(handoffItem.downloadsIssued, 0);
  assert.equal(handoffItem.expiresAt, NOW + HANDOFF_TTL_SECONDS);
  assert.equal(puts[1].input.ConditionExpression, "attribute_not_exists(transactionHash)");
});

test("repeat claim within budget reissues with an optimistic lock", async () => {
  const existing = {
    transactionHash: HASH,
    claimID: "11111111-2222-4333-8444-555566667777",
    reissueCount: 2,
    reissueWindowStart: NOW - 60,
  };
  const store = fakeStore({
    GetCommand: () => ({ Item: existing }),
    UpdateCommand: () => ({}),
    PutCommand: () => ({}),
  });

  const claimID = await recordClaim({
    store,
    tableName: TABLE,
    transactionHash: HASH,
    originalPurchaseDate: "2026-08-13T18:42:00Z",
    now: NOW,
    newClaimID: () => UUID,
  });

  assert.equal(claimID, UUID);
  const update = store.sent.find((command) => command instanceof UpdateCommand);
  assert.ok(update, "expected a conditional update");
  assert.equal(update.input.ExpressionAttributeValues[":claimID"], UUID);
  assert.equal(update.input.ExpressionAttributeValues[":count"], 3);
  assert.equal(update.input.ExpressionAttributeValues[":windowStart"], NOW - 60);
  assert.equal(update.input.ExpressionAttributeValues[":previousClaimID"], existing.claimID);
  assert.match(update.input.ConditionExpression, /claimID = :previousClaimID/);

  const handoffPut = store.sent.find((command) => command instanceof PutCommand);
  assert.equal(handoffPut.input.Item.transactionHash, `handoff#${UUID}`);
});

test("repeat claim past the budget throws without writing", async () => {
  const store = fakeStore({
    GetCommand: () => ({
      Item: {
        transactionHash: HASH,
        claimID: "11111111-2222-4333-8444-555566667777",
        reissueCount: REISSUE_LIMIT,
        reissueWindowStart: NOW - 60,
      },
    }),
  });

  await assert.rejects(() => recordClaim({
    store,
    tableName: TABLE,
    transactionHash: HASH,
    originalPurchaseDate: "2026-08-13T18:42:00Z",
    now: NOW,
    newClaimID: () => UUID,
  }));
  assert.equal(store.sent.filter((command) => !(command instanceof GetCommand)).length, 0);
});

test("an expired window resets the reissue budget", async () => {
  const store = fakeStore({
    GetCommand: () => ({
      Item: {
        transactionHash: HASH,
        claimID: "11111111-2222-4333-8444-555566667777",
        reissueCount: REISSUE_LIMIT,
        reissueWindowStart: NOW - REISSUE_WINDOW_SECONDS - 1,
      },
    }),
    UpdateCommand: () => ({}),
    PutCommand: () => ({}),
  });

  await recordClaim({
    store,
    tableName: TABLE,
    transactionHash: HASH,
    originalPurchaseDate: "2026-08-13T18:42:00Z",
    now: NOW,
    newClaimID: () => UUID,
  });

  const update = store.sent.find((command) => command instanceof UpdateCommand);
  assert.equal(update.input.ExpressionAttributeValues[":count"], 1);
  assert.equal(update.input.ExpressionAttributeValues[":windowStart"], NOW);
});

test("a legacy record without reissue fields counts as zero reissues", async () => {
  const store = fakeStore({
    GetCommand: () => ({
      Item: {
        transactionHash: HASH,
        claimID: "11111111-2222-4333-8444-555566667777",
        status: "pending_one_time_handoff",
      },
    }),
    UpdateCommand: () => ({}),
    PutCommand: () => ({}),
  });

  await recordClaim({
    store,
    tableName: TABLE,
    transactionHash: HASH,
    originalPurchaseDate: "2026-08-13T18:42:00Z",
    now: NOW,
    newClaimID: () => UUID,
  });

  const update = store.sent.find((command) => command instanceof UpdateCommand);
  assert.equal(update.input.ExpressionAttributeValues[":count"], 1);
});

test("handoff consumption increments the download count", async () => {
  const store = fakeStore({
    GetCommand: (input) => {
      assert.deepEqual(input.Key, { transactionHash: `handoff#${UUID}` });
      assert.equal(input.ConsistentRead, true);
      return { Item: { transactionHash: `handoff#${UUID}`, downloadsIssued: 1, expiresAt: NOW + 60 } };
    },
    UpdateCommand: (input) => {
      assert.match(input.ConditionExpression, /downloadsIssued < :max/);
      assert.match(input.ConditionExpression, /expiresAt > :now/);
      assert.equal(input.ExpressionAttributeValues[":max"], DOWNLOADS_PER_HANDOFF);
      return {};
    },
  });

  await consumeHandoff({ store, tableName: TABLE, token: UUID, now: NOW });
});

test("handoff consumption rejects junk, unknown, expired, and exhausted tokens", async () => {
  const cases = [
    { token: "not-a-uuid", handlers: {} },
    { token: UUID, handlers: { GetCommand: () => ({}) } },
    {
      token: UUID,
      handlers: { GetCommand: () => ({ Item: { downloadsIssued: 0, expiresAt: NOW - 1 } }) },
    },
    {
      token: UUID,
      handlers: {
        GetCommand: () => ({ Item: { downloadsIssued: DOWNLOADS_PER_HANDOFF, expiresAt: NOW + 60 } }),
      },
    },
  ];

  for (const { token, handlers } of cases) {
    const store = fakeStore(handlers);
    await assert.rejects(() => consumeHandoff({ store, tableName: TABLE, token, now: NOW }));
    assert.equal(store.sent.filter((command) => command instanceof UpdateCommand).length, 0);
  }
});
