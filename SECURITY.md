# Security Policy

## Supported Versions
| Version | Supported |
|---------|-----------|
| 1.1.x   | |
| <1.1    | please upgrade |

## Reporting a Vulnerability
- Email: **zahin26112004@gmail.com** with subject `[SECURITY]`
- Or open a private GitHub Security Advisory.
- We will acknowledge within 72h and aim to patch within 14 days.

## Supply Chain
- GGUF downloads verified by `MinBytes` + optional `SHA256` (see `models/catalog.json`). We recommend pinning `versions.env` and verifying `SHA256SUMS` for Ollama/AnythingLLM artifacts.
- No telemetry leaves the USB. AnythingLLM data lives under `anythingllm_data/` on the drive. Loss of USB = plaintext chats — consider encrypting the drive with BitLocker/VeraCrypt (see `todo.md` P3).

## Best Practices
- Reformat USB as **exFAT** or **ext4** (FAT32 cannot hold >4 GB GGUFs).
- Use pinned `versions.env` URLs, not `latest` in production.
- Verify checksums before large offline deployments.
