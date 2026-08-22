import { createHash, createHmac, randomUUID } from "node:crypto";

import {
  AppStoreServerAPIClient,
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";
import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";

const EXPECTED_BUNDLE_ID = process.env.APP_STORE_BUNDLE_ID;
const EXPECTED_APP_APPLE_ID = Number(process.env.APP_APPLE_ID);
const ONE_YEAR_SECONDS = 60 * 60 * 24 * 365;
const APPLE_ROOT_CERTIFICATES = [
  `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`,
];

const secrets = new SecretsManagerClient({});
const claims = DynamoDBDocumentClient.from(new DynamoDBClient({}));
let appStoreKeyPromise;
let claimHashKeyPromise;

function json(statusCode, body) {
  return {
    statusCode,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
    body: JSON.stringify(body),
  };
}

export function parseClaimRequest(body) {
  if (typeof body !== "string" || body.length > 4_096) {
    throw new Error("invalid request body");
  }

  const request = JSON.parse(body);
  if (
    !request ||
    typeof request.appTransactionID !== "string" ||
    request.appTransactionID.length < 8 ||
    request.appTransactionID.length > 256 ||
    request.bundleID !== EXPECTED_BUNDLE_ID ||
    typeof request.originalPurchaseDate !== "string" ||
    !Number.isFinite(Date.parse(request.originalPurchaseDate))
  ) {
    throw new Error("invalid claim request");
  }

  return request;
}

async function getSecretString(secretArn) {
  const result = await secrets.send(new GetSecretValueCommand({ SecretId: secretArn }));
  if (!result.SecretString) {
    throw new Error("claim secret is unavailable");
  }
  return result.SecretString;
}

async function appStoreKey() {
  appStoreKeyPromise ??= getSecretString(process.env.APP_STORE_PRIVATE_KEY_SECRET_ARN);
  return appStoreKeyPromise;
}

async function claimHashKey() {
  claimHashKeyPromise ??= getSecretString(process.env.CLAIM_HASH_SECRET_ARN)
    .then((secret) => JSON.parse(secret).key);
  return claimHashKeyPromise;
}

function createVerifier() {
  return new SignedDataVerifier(
    APPLE_ROOT_CERTIFICATES.map((certificate) => Buffer.from(certificate)),
    true,
    Environment.PRODUCTION,
    EXPECTED_BUNDLE_ID,
    EXPECTED_APP_APPLE_ID,
  );
}

async function verifyAppTransaction(appTransactionID) {
  const privateKey = await appStoreKey();
  const client = new AppStoreServerAPIClient(
    privateKey,
    process.env.APP_STORE_KEY_ID,
    process.env.APP_STORE_ISSUER_ID,
    EXPECTED_BUNDLE_ID,
    Environment.PRODUCTION,
  );
  const response = await client.getAppTransactionInfo(appTransactionID);
  const transaction = await createVerifier().verifyAndDecodeAppTransaction(
    response.signedAppTransactionInfo,
  );

  if (
    transaction.bundleId !== EXPECTED_BUNDLE_ID ||
    transaction.appAppleId !== EXPECTED_APP_APPLE_ID ||
    transaction.appTransactionId !== appTransactionID
  ) {
    throw new Error("app transaction does not belong to System Headroom");
  }

  return transaction;
}

function configuredHandoffBaseUrl() {
  const value = process.env.CLAIM_HANDOFF_BASE_URL;
  if (!value) {
    return undefined;
  }
  const url = new URL(value);
  if (url.protocol !== "https:" || !url.hostname) {
    throw new Error("claim handoff URL must be HTTPS");
  }
  return url.toString().replace(/\/$/, "");
}

export async function health() {
  return json(200, { status: "ok", claimFlowEnabled: process.env.CLAIM_FLOW_ENABLED === "true" });
}

export async function handler(event) {
  if (process.env.CLAIM_FLOW_ENABLED !== "true") {
    return json(503, { error: "claim flow is not enabled" });
  }

  let request;
  try {
    request = parseClaimRequest(event.body);
  } catch {
    return json(400, { error: "invalid claim request" });
  }

  try {
    const handoffBaseUrl = configuredHandoffBaseUrl();
    if (!handoffBaseUrl) {
      throw new Error("protected handoff is not configured");
    }

    const transaction = await verifyAppTransaction(request.appTransactionID);
    const transactionHash = createHmac("sha256", await claimHashKey())
      .update(request.appTransactionID)
      .digest("base64url");
    const claimID = randomUUID();
    const now = Math.floor(Date.now() / 1_000);

    await claims.send(new PutCommand({
      TableName: process.env.CLAIMS_TABLE_NAME,
      Item: {
        transactionHash,
        claimID,
        originalPurchaseDate: transaction.originalPurchaseDate,
        validatedAt: new Date().toISOString(),
        expiresAt: now + ONE_YEAR_SECONDS,
        status: "pending_one_time_handoff",
      },
      ConditionExpression: "attribute_not_exists(transactionHash)",
    }));

    return json(201, { claimURL: `${handoffBaseUrl}/${claimID}` });
  } catch (error) {
    console.error("claim verification failed", {
      kind: error instanceof Error ? error.name : "unknown",
      correlationID: createHash("sha256").update(randomUUID()).digest("hex"),
    });
    return json(503, { error: "claim verification is unavailable" });
  }
}
