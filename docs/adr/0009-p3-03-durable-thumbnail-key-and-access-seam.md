---
status: proposed
date: 2026-10-24
---

# ADR-009: P3-03 needs a lease-bound thumbnail cache seam

## WI-0 evidence

`P303DurabilityProbeTests` uses real TIFF bytes and an atomic replacement with the same byte count and restored modification date. The two `FileRevisionReader` values differ only by their session resource tokens, and both `RenderKey.persistentEncoding` values are nil. Streaming SHA-256 distinguishes the bytes. It also confirms that `AccessImageSource` holds a `FileAccess` lease before requesting and decoding through a real `ImageIOPipeline`.

The same probe calls the public `ImageIOPipeline.request(for:maximumPixelSize:identityRoot:)` and `image(for:)` directly, with a caller-supplied root, and obtains pixels without any `AccessLeasing` instance. `ImageDecodeRequest` and `ItemIdentityRoot` are publicly constructible. A disk lookup added to that public pipeline route would have no enforceable proof that authorization was obtained or remains valid. Adding the store there would violate issue #107's access condition even if the normal App caller uses `AccessImageSource`.

## Proposed decision, pending scope amendment

1. Add a narrow cache port to `Packages/PicseeKit/Sources/PicseeCore/Ports/` and call it only within `AccessImageSource.image`'s existing `access.withLease` closure. Inject its Infrastructure implementation from `App/PicseeApp.swift`. The public `ImageIOPipeline` APIs continue to decode but have no disk-cache lookup. This requires authorization to edit `Packages/PicseeKit/Sources/PicseeApplication/Access/AccessImageSource.swift` and the new Core port file; the current P3-03 brief does not own those paths.
2. The cache port accepts only requested thumbnail renders with a root-relative `ItemID`. Its implementation hashes the source with streaming SHA-256 on an off-main executor while the lease is live. Start with a 32 MiB source-file eligibility ceiling, 1 MiB chunks, a cancellation check per chunk, and a post-hash path revision check. A file over the ceiling, an unreadable file, an unverifiable root identity, or a cancelled request skips persistence and follows normal decode. Hashing occurs for requested eligible thumbnails only, never during a folder scan. The ceiling is an initial policy to test, not a measured optimal value.
3. Include the content digest, stable root-relative item encoding, frame/page, edge, preview mode, purpose, orientation/color/alpha/HDR policy, decoder version, encoder version, and cache schema version in a new length-delimited persistent encoding; SHA-256 of that encoding names the payload. Never hash `RenderKey.stableEncoding` or drop its resource token. The content digest replaces the session token as durable revision evidence; the token remains useful for same-session source-change checks.
4. On a hit, validate a current access lease and source identity/revision, compute the digest, and recheck the source after payload read before delivery. On a miss, decode under the same lease; verify the decoded image revision and source evidence before publishing a payload. A source replacement during hash/decode must fail or retry as a normal miss; no old-key write may publish new pixels. A same-inode, same-size, same-time in-place rewrite during hashing needs a stronger snapshot strategy or a documented skip condition before implementation can claim this case.

## Measured key cost and limits

Mac16,10, 16 GiB RAM, macOS 26.4, Xcode 26.6. A local Swift CryptoKit probe streamed 1 MiB chunks from local files, five sequential runs per file; timings exclude Swift compilation and image decode. The first run may include filesystem cache effects. These are single-machine observations, not a 5,000-item benchmark.

| Asset | Bytes | Five hash times (ms) | Median (ms) | Initial eligibility |
|---|---:|---|---:|---|
| Synthetic coordinate PNG | 15,599 | 0.293, 0.031, 0.025, 0.020, 0.021 | 0.025 | yes |
| Real HEIC SDR photo | 4,479,456 | 2.828, 1.689, 1.613, 1.623, 1.627 | 1.627 | yes |
| Real JPEG SDR photo | 10,500,045 | 5.390, 4.065, 3.903, 3.952, 4.018 | 4.018 | yes |
| Generated noisy 48 MP PNG | 48,020,708 | not hashed | — | no, over 32 MiB |
| Generated noisy 100 MP PNG | 100,040,573 | not hashed | — | no, over 32 MiB |

The probe did not run in a signed sandbox, under concurrent decode, on a cold storage device, or across 5,000 items. It does not establish a full-cache speedup. P3-08 must measure those conditions and may change the eligibility ceiling.

## Consequences

P3-03 stops at WI-0 until the two access/port paths are added to its ownership or a separately assigned change creates the seam. No SQLite store or cache payload is built yet. `CACHE-02` remains Absent and `ACCESS-04` remains Absent. After the seam is authorized, use Swift RED receipts for the first observable cache behavior and implement storage, restart/replacement/corruption tests, then end-to-end lease denial tests. P3-04 still owns repair, eviction, and read/write leases; P3-05 owns clear generation; P3-08 owns scale and device evidence.
