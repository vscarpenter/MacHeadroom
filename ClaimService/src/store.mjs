import { GetCommand, PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";

// Reissue and handoff policy. Published in Documentation/DirectEditionClaimAPI.md;
// keep the two in sync.
export const REISSUE_LIMIT = 5;
export const REISSUE_WINDOW_SECONDS = 60 * 60 * 24 * 30;
export const HANDOFF_TTL_SECONDS = 60 * 60 * 24;
export const DOWNLOADS_PER_HANDOFF = 3;
export const CLAIM_TTL_SECONDS = 60 * 60 * 24 * 365;

const HANDOFF_TOKEN_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/// Records a verified claim, minting a fresh one-time handoff token. A repeat
/// claim for the same transaction reissues within a rate-limited budget so a
/// failed download or a new Mac never needs manual support. Returns the claim
/// identifier that becomes the handoff URL's token.
export async function recordClaim({
  store,
  tableName,
  transactionHash,
  originalPurchaseDate,
  now,
  newClaimID,
}) {
  const existing = (await store.send(new GetCommand({
    TableName: tableName,
    Key: { transactionHash },
    ConsistentRead: true,
  }))).Item;

  const claimID = newClaimID();
  const validatedAt = new Date(now * 1_000).toISOString();

  if (!existing) {
    await store.send(new PutCommand({
      TableName: tableName,
      Item: {
        transactionHash,
        claimID,
        originalPurchaseDate,
        validatedAt,
        expiresAt: now + CLAIM_TTL_SECONDS,
        status: "active",
        reissueCount: 0,
        reissueWindowStart: now,
      },
      ConditionExpression: "attribute_not_exists(transactionHash)",
    }));
  } else {
    const windowStart = existing.reissueWindowStart ?? 0;
    const windowExpired = now - windowStart >= REISSUE_WINDOW_SECONDS;
    const spent = windowExpired ? 0 : (existing.reissueCount ?? 0);
    if (spent >= REISSUE_LIMIT) {
      throw new Error("claim reissue budget exhausted");
    }

    await store.send(new UpdateCommand({
      TableName: tableName,
      Key: { transactionHash },
      UpdateExpression:
        "SET claimID = :claimID, reissueCount = :count, "
        + "reissueWindowStart = :windowStart, expiresAt = :expiresAt, "
        + "validatedAt = :validatedAt, #status = :status",
      ConditionExpression: "claimID = :previousClaimID",
      ExpressionAttributeNames: { "#status": "status" },
      ExpressionAttributeValues: {
        ":claimID": claimID,
        ":count": spent + 1,
        ":windowStart": windowExpired ? now : windowStart,
        ":expiresAt": now + CLAIM_TTL_SECONDS,
        ":validatedAt": validatedAt,
        ":status": "active",
        ":previousClaimID": existing.claimID,
      },
    }));
  }

  await store.send(new PutCommand({
    TableName: tableName,
    Item: {
      transactionHash: `handoff#${claimID}`,
      claimTransactionHash: transactionHash,
      downloadsIssued: 0,
      expiresAt: now + HANDOFF_TTL_SECONDS,
    },
    ConditionExpression: "attribute_not_exists(transactionHash)",
  }));

  return claimID;
}

/// Shared read-only validation: throws unless the token is well-formed and
/// its item exists, is unexpired (TTL deletion lags in DynamoDB, so expiry
/// is enforced here as well as in the update condition), and has slots left.
async function readRedeemableHandoff({ store, tableName, token, now }) {
  if (typeof token !== "string" || !HANDOFF_TOKEN_PATTERN.test(token)) {
    throw new Error("invalid handoff token");
  }

  const key = { transactionHash: `handoff#${token}` };
  const item = (await store.send(new GetCommand({
    TableName: tableName,
    Key: key,
    ConsistentRead: true,
  }))).Item;

  if (!item || item.expiresAt <= now || item.downloadsIssued >= DOWNLOADS_PER_HANDOFF) {
    throw new Error("handoff token is not redeemable");
  }

  return key;
}

/// Read-only redeemability check. The handler peeks before the failure-prone
/// S3 manifest read so a transient failure there never costs a download slot;
/// only consumeHandoff spends one.
export async function peekHandoff({ store, tableName, token, now }) {
  await readRedeemableHandoff({ store, tableName, token, now });
}

/// Redeems a one-time handoff token for one download slot. Self-validating —
/// safe to call without a preceding peek — and the conditional update alone
/// enforces the cap under concurrency.
export async function consumeHandoff({ store, tableName, token, now }) {
  const key = await readRedeemableHandoff({ store, tableName, token, now });

  await store.send(new UpdateCommand({
    TableName: tableName,
    Key: key,
    UpdateExpression: "SET downloadsIssued = downloadsIssued + :one",
    ConditionExpression: "downloadsIssued < :max AND expiresAt > :now",
    ExpressionAttributeValues: {
      ":one": 1,
      ":max": DOWNLOADS_PER_HANDOFF,
      ":now": now,
    },
  }));
}
