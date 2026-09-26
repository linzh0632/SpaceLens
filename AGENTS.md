# SpaceLens repository notes

- SpaceLens is a local, read-only macOS Quick Look extension. Do not add telemetry, file uploads, remote rendering, or execution of previewed content.
- Keep the host app preview-only: it must not declare document-opening roles or become a default file opener.
- Run `./scripts/release-check.sh` before merging user-visible changes.
- Put temporary fixtures in `build/fixtures/<feature>` and delete them after verification. Never commit credentials, personal files, build products, or signing material.
- Update user-facing documentation when supported formats, installation steps, privacy behavior, or limitations change.
