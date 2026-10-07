# EmbeddingGemma 2 semantic search

Version 0.0.2 combines offline Korean/English/Japanese text retrieval with image,
PDF-page and audio retrieval in the app and MCP. Search must match current revisions
and filters, preserve immutable originals and history, release idle model memory,
avoid model startup for empty libraries and retain keyword fallback on failure.

The packaged model is [EmbeddingGemma 2](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2),
using the [ggml-org Q8_0 GGUF model and Q8_0 multimodal projector](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF)
with llama.cpp b11468. Text, image and audio embeddings share 768 dimensions.
The bundled multimodal projector contains both vision and audio encoders; the
full runtime loads the 740M-parameter model, while text-only operation loads the
270M-parameter text backbone and embedder.
Model, projector and runtime revisions and SHA-256 values are pinned in
`scripts/prepare-embedding.py`; full Apache 2.0 model license and runtime notices
are bundled. There is no runtime model download. Video indexing is not implemented.

One private Unix-socket worker per library owns the inference process. A process lock
prevents duplicate workers when the app and MCP start together. The runtime listens
only on loopback with a generated API key; clients use the private socket. Model and
worker terminate after 60 seconds without foreground or indexing work. Query work is
served between background passage or media operations. The multimodal runtime uses
an 8,192-token context. Queries during indexing reuse that runtime. Once the indexing
queue drains, the worker stops it and proactively starts the text-query runtime
with a 2,048-token context and no projector. Only one inference process is owned
by the worker at a time.
This is a memory-management policy, not a measured memory guarantee.

A derived cache outside wiki.sqlite3 is regenerable; it never changes originals,
revisions or backups. The cache identity includes both model and projector hashes
and the input preparation version. Upgrading from 0.0.1 automatically builds a
new derived index; old vectors are not mixed with the new model's vector space.

Text requests have a 512-token bound. Paragraph inputs preserve headings and titles,
with a 384-token passage target including the title and heading prefix.
Text documents use `title: {title} | text: {content}` and queries use
`task: search result | query: {query}`. Media inputs do not substitute filenames,
generated descriptions or transcripts for the original content.

Material indexing queues identities and loads one original chunk at a time:

| Material | Indexed input | Location retained |
| --- | --- | --- |
| Readable text | Title and text paragraphs | Original extraction snapshot and page, when present |
| Image | Native decoded image, preserving aspect ratio and capped at 2,048 pixels on the longest side without upscaling | Original material |
| PDF | Existing extracted text and a rendered image of every page | Original page number |
| Audio | Consecutive 20-second chunks converted locally to mono 16 kHz PCM16 WAV | Start and end seconds |

Animated images use the first frame. Audio extensions are `wav`, `mp3`, `m4a`,
`aac`, `flac`, `aiff`, `aif` and `caf`, subject to the actual format being readable
by macOS AVAudioFile. Native audio inputs must have a sample rate from 8 to 384 kHz
and at most 32 channels. PDF pages and audio chunks are processed in order without
sampling away pages or truncating the recording. More than 100,000 PDF pages or
audio chunks causes the material to fail the resource guard instead of silently
indexing a partial file. Original hashes are checked
before using material bytes. A damaged, locked or unsupported material is recorded
as a failure while other materials continue indexing; a partial index is not
reported as complete.

Visual and audio matches identify a page or time interval. They are not OCR,
transcription or verified quotations. Exact citation validation continues to use
preserved readable original text and extraction snapshots.
Opening a result navigates to its PDF page or positions the native audio player
at the matched segment start without automatically playing it.

Queries scan vector batches of 256 within a read snapshot. Cache keys include
the asset identity, input preparation version and exact input. Search rechecks
current page revision/content, archive state and tags. Page search combines
keyword candidates and the top 20 semantic page candidates using reciprocal rank
fusion (RRF).

Material search takes up to 20 material candidates from each of the text, image
and audio rankings and forms their union. Within that union, each material keeps
its highest-cosine match as evidence. Candidates are sorted globally by cosine in
EmbeddingGemma 2's shared normalized vector space. The global top 20 semantic
candidates are then combined with keyword candidates using RRF. The displayed
page or audio interval comes from the retained match.
Similarity is not a claim of answerability. Unified active materials use the same
worker for text and media retrieval; old source-search and archived searches retain
keyword behavior. Incomplete index coverage is reported as warming, not evidence
of absence; material failures produce a partial state.

Validation: derived-cache integrity, stale vector exclusion, filters, token bounds,
multilingual and multimodal real-model MCP searches, page/time provenance,
per-material failures, two clients sharing one worker, idle exit,
restart/cache reuse, fallback and packaged resource/signature checks.
