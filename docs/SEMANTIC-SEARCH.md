# EmbeddingGemma semantic search

Acceptance: packaged offline Korean/English/Japanese hybrid retrieval in both the app
and MCP, matching current revisions and filters; immutable originals/history preserved;
model idle release; no model startup for empty libraries; keyword fallback on failure.

Use the checksum-pinned EmbeddingGemma Q8_0 (768 dimensions) and llama.cpp b11371.
The packaged app includes model bytes, native runtime, license and NOTICE. There is no
runtime model download. Gemma's usage/distribution terms accompany the model.

One private Unix-socket worker per library owns the inference process. A process lock
prevents duplicate workers when the app and MCP start together. The runtime listens
only on loopback with a generated API key; clients use the private socket. Model and
worker terminate after 60 seconds without foreground or indexing work. Query work is
served between background passage operations. A derived cache outside wiki.sqlite3
is regenerable; it never changes originals, revisions or backups.

Paragraph inputs preserve headings and titles. Tokenization enforces the 512-token
runtime context, with a 384-token passage target. Material indexing queues identities and loads one original at a time. Queries scan vector batches of 256 within a read snapshot.
Cache keys include the model digest,
chunking version and exact input. Search rechecks current page revision/content,
archive state and tags. Reciprocal rank fusion combines exact keyword candidates and the top 20 semantic
page candidates. Gemma cosine values do not use Qwen's fixed threshold; ranking is
not a claim of answerability. Unified active materials use the same worker for title/paragraph retrieval; old source-search and archived searches retain keyword behavior. Incomplete
index coverage is reported as warming, not evidence of absence.

Validation: derived-cache integrity, stale vector exclusion, filters, token bounds,
multilingual real-model MCP searches, two clients sharing one worker, idle exit,
restart/cache reuse, fallback and packaged resource/signature checks.
