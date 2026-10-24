# Bundled FreeCM subset

These files are copied from FreeCM 0.1.158, commit
`3f867e99750bd746f690c6ad168e1d488e915eae` of
<https://github.com/NorthBoundWisdom/FreeCM>.

Copyright (c) 2026 FreeCM. The imported files remain available under the MIT
license reproduced in [LICENSE](LICENSE).

This snapshot contains only command validation, JSONC parsing, subprocess and
workspace-lock helpers, the Android workflow adapter, and their version/error
helpers. Source-root/dependency management, asset management, C++/CMake, Swift,
.NET, the VS Code extension, hooks and development tooling are excluded.
No upstream Git checkout, package installation or FreeCM service is needed.

Original source hashes and local adaptations are recorded in
[UPSTREAM.json](UPSTREAM.json). The package initializer exposes only the retained
version API, and the workspace-lock protocol constants are defined locally so
that locking does not load a source-root schema.

Immivio maintains this open-source copy independently. Local adaptations may be
made here while retaining these notices; `UPSTREAM.json` identifies the original
import, and build receipts also record a digest of the current bundled files.
