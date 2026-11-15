const crypto = require('crypto');

function hmac(key, data) {
  return crypto.createHmac('sha256', key).update(data);
}

function sha256(data) {
  return crypto.createHash('sha256').update(data).digest('hex');
}

function getSignatureKey(key, dateStamp, regionName, serviceName) {
  const kDate = hmac('AWS4' + key, dateStamp).digest();
  const kRegion = hmac(kDate, regionName).digest();
  const kService = hmac(kRegion, serviceName).digest();
  const kSigning = hmac(kService, 'aws4_request').digest();
  return kSigning;
}

async function s3Request({
  accountId,
  bucket,
  key,
  method = 'GET',
  body = null,
  contentType = 'application/octet-stream',
  accessKeyId,
  secretAccessKey,
}) {
  const host = `${bucket}.${accountId}.r2.cloudflarestorage.com`;
  const endpoint = `https://${host}/${encodeURI(key)}`;

  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.substring(0, 8);
  const region = 'auto';
  const service = 's3';

  const payloadHash = body ? sha256(body) : sha256('');

  const headers = {
    'host': host,
    'x-amz-date': amzDate,
    'x-amz-content-sha256': payloadHash,
  };

  if (body) {
    headers['content-type'] = contentType;
    headers['content-length'] = Buffer.byteLength(body).toString();
  }

  // Canonical headers (sorted lowercase)
  const headerKeys = Object.keys(headers).sort();
  const canonicalHeaders = headerKeys.map(k => `${k}:${headers[k]}\n`).join('');
  const signedHeaders = headerKeys.join(';');

  const canonicalUri = '/' + key.split('/').map(encodeURIComponent).join('/');
  const canonicalRequest = [
    method,
    canonicalUri,
    '', // query string
    canonicalHeaders,
    signedHeaders,
    payloadHash,
  ].join('\n');

  const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    credentialScope,
    sha256(canonicalRequest),
  ].join('\n');

  const signingKey = getSignatureKey(secretAccessKey, dateStamp, region, service);
  const signature = hmac(signingKey, stringToSign).digest('hex');

  const authorization = `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const reqHeaders = { ...headers, 'Authorization': authorization };
  delete reqHeaders['host']; // fetch sets host automatically

  const res = await fetch(endpoint, {
    method,
    headers: reqHeaders,
    body: body || undefined,
  });

  return res;
}

module.exports = { s3Request, sha256 };

