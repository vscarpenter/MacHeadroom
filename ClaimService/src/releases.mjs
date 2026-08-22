import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

export const DOWNLOAD_URL_TTL_SECONDS = 15 * 60;
const RELEASE_KEY_PREFIX = "updates/";

const s3 = new S3Client({});

/// Reads the publish pipeline's manifest describing the current Direct DMG.
/// The key must stay inside the updates/ prefix — the only prefix the
/// handoff role may read or presign.
export async function latestRelease({
  client = s3,
  bucket = process.env.RELEASE_BUCKET_NAME,
} = {}) {
  const result = await client.send(new GetObjectCommand({
    Bucket: bucket,
    Key: "updates/latest.json",
  }));
  const release = JSON.parse(await result.Body.transformToString());

  if (
    typeof release.key !== "string" ||
    !release.key.startsWith(RELEASE_KEY_PREFIX) ||
    release.key.includes("..") ||
    typeof release.version !== "string" ||
    typeof release.sha256 !== "string"
  ) {
    throw new Error("release manifest is invalid");
  }

  return release;
}

/// Presigns a short-lived download for one release object.
export function presignDownload(key, {
  client = s3,
  bucket = process.env.RELEASE_BUCKET_NAME,
} = {}) {
  return getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), {
    expiresIn: DOWNLOAD_URL_TTL_SECONDS,
  });
}
