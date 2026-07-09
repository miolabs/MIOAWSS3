# MIOAWSS3

A **thin** Amazon S3 client for Swift, built directly on `URLSession` and
[AWS Signature V4](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html).

## Purpose

The official [aws-sdk-swift](https://github.com/awslabs/aws-sdk-swift) is generated for
the whole AWS surface: it pulls in Smithy, the CRT runtime and dozens of modules, which
means a huge download and several minutes of compile time — just to PUT and GET some
bytes in a bucket.

MIOAWSS3 exists to avoid that. It is deliberately a **thin layer** over the S3 HTTP
API: it signs plain `URLRequest`s with Signature V4 and sends them with `URLSession`.
The only dependency is [swift-crypto](https://github.com/apple/swift-crypto) (for
SHA-256/HMAC), so a clean build takes seconds instead of minutes.

**What it does:**

- Upload (`putObject`), download (`getObject`) and delete (`deleteObject`) objects.
- Optional canned ACL (`x-amz-acl`) and `Content-Type` on uploads.
- `async/await` API, plus blocking variants for legacy synchronous call sites.
- Works with AWS S3 (virtual-hosted URLs) and S3-compatible services such as MinIO or
  DigitalOcean Spaces (path-style URLs via a custom endpoint).
- Typed errors with the S3 error `Code`/`Message` parsed from the XML response.
- Linux-compatible (`FoundationNetworking`).

**What it intentionally does not do:** multipart / chunked-streaming uploads (a single
signed PUT covers up to 5 GB), bucket management, listing, presigned URLs, or any other
AWS service. If you need the full API surface, use the official SDK — this library is
for the common "store bytes / read bytes" case where the SDK is overkill.

## Libraries

| Product | What it is |
|---------|------------|
| `MIOAWSS3` | The S3 client: `S3Wrapper`, `S3ACL`, `S3Error`. This is what apps normally import. |
| `MIOAWSCore` | The service-agnostic building blocks: `SigV4Signer` (Signature V4 request signing) and `AWSCredentials`. Reusable to call other AWS APIs by hand. |

The targets are prefixed `MIO` on purpose, so they never clash with the official SDK's
`AWSS3`/`AWSCore` module names if both end up in the same dependency graph during a
migration.

## Installation

```swift
// Package.swift
dependencies: [
    .package( url: "https://github.com/miolabs/MIOAWSS3.git", branch: "master" )
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product( name: "MIOAWSS3", package: "MIOAWSS3" )
        ]
    )
]
```

## Examples

### Upload, download, delete

```swift
import MIOAWSS3

let s3 = S3Wrapper( region: "eu-west-1", key: ACCESS_KEY, secret: SECRET_KEY )

// Upload raw bytes
try await s3.putObject( data: imageData,
                        path: "/images/2026/07/photo.png",
                        bucket: "my-bucket" )

// Upload publicly readable, with an explicit content type
try await s3.putObject( data: jsonData,
                        path: "/exports/report.json",
                        bucket: "my-bucket",
                        acl: .publicRead,
                        mimeType: "application/json" )

// Download
let data = try await s3.getObject( path: "/images/2026/07/photo.png", bucket: "my-bucket" )

// Delete
try await s3.deleteObject( path: "/images/2026/07/photo.png", bucket: "my-bucket" )
```

### Blocking (non-async) call sites

Every method also has a synchronous variant for code that cannot adopt `async` yet.
It blocks only the calling thread — the request runs on URLSession's own queue, so the
Swift concurrency cooperative pool is never starved:

```swift
let data = try s3.getObject( path: "/config/settings.json", bucket: "my-bucket" )
```

### S3-compatible services (MinIO, DigitalOcean Spaces...)

Passing a custom endpoint switches to path-style addressing
(`{endpoint}/{bucket}/{key}`):

```swift
let s3 = S3Wrapper( region: "us-east-1",
                    key: "minioadmin", secret: "minioadmin",
                    endpoint: URL( string: "http://localhost:9000" ) )

try await s3.putObject( data: data, path: "backup.bin", bucket: "backups" )
```

### Error handling

Failed requests throw `S3Error.requestFailed` with the HTTP status and the S3 error
code/message parsed from the XML body:

```swift
do {
    _ = try await s3.getObject( path: "/missing.txt", bucket: "my-bucket" )
}
catch let S3Error.requestFailed( statusCode, code, message ) {
    // statusCode: 404, code: "NoSuchKey", message: "The specified key does not exist."
    print( "S3 error \(statusCode): \(code ?? "?") - \(message ?? "?")" )
}
```

### Signing your own requests to other AWS services

`MIOAWSCore` is not tied to S3 — `SigV4Signer` can sign a request for any AWS service:

```swift
import MIOAWSCore

let credentials = AWSCredentials( accessKey: ACCESS_KEY, secretKey: SECRET_KEY )
let signer      = SigV4Signer( service: "sqs", region: "eu-west-1" )

var request = URLRequest( url: URL( string: "https://sqs.eu-west-1.amazonaws.com/..." )! )
request.httpMethod = "GET"
try signer.sign( request: &request, credentials: credentials, bodyHash: SigV4Signer.emptyBodySHA256 )

let (data, response) = try await URLSession.shared.data( for: request )
```

## Implementation notes

- The ACL is sent as a signed `x-amz-acl` header on the PUT itself — no separate
  `PutObjectAcl` round-trip.
- Object keys are URI-encoded per the SigV4 spec (spaces, UTF-8, `+`, `$`... are safe).
- The signer is verified against the official AWS Signature V4 test examples — see
  `Tests/MIOAWSS3Tests/SigV4SignerTests.swift`.
