# Semantic search

Galpium combines keyword retrieval with offline EmbeddingGemma 2 retrieval.
Wiki text and original materials share the same search service in the app and
MCP. Images, PDF pages and audio can be indexed directly and searched with text
queries. Search locates candidates; citations still require exact evidence from
preserved original text.

## Model assets

The bundled model is [EmbeddingGemma 2](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2),
using the [ggml-org Q8_0 GGUF model and multimodal projector](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF)
with llama.cpp. Text, image and audio embeddings use one normalized
768-dimensional space. The projector contains vision and audio encoders.

Model, projector and runtime revisions and SHA-256 values are pinned in
[prepare-embedding.py](https://github.com/KimEJ/Galpium/blob/main/scripts/prepare-embedding.py).
The application bundles these assets with their licenses and notices; it does
not download a model during use. Release-specific changes are listed in the
[change history](CHANGELOG.md).

## Indexed inputs

Text passages retain titles and heading context. Each passage is limited to
384 tokens including its prefix, and text inference requests are limited to
512 tokens. Document inputs use `title: {title} | text: {content}`; queries use
`task: search result | query: {query}`. Markdown tables and list rows contribute
text alongside ordinary paragraphs.

| Original | Indexed input | Retained location |
| --- | --- | --- |
| Readable text | Title and text passages from preserved extractions | Original page, when present |
| Image | Decoded image converted to JPEG, preserving aspect ratio and capped at 2,048 pixels on the longest side | Original material |
| PDF | Extracted text and a rendered image of every page | Original page number |
| Audio | Consecutive 20-second segments converted locally to mono 16 kHz PCM16 WAV | Start and end seconds |

PDFKit and ImageIO prepare visual inputs; AVFoundation prepares audio. Animated
images use the first frame. Transparent pixels are composited on white for JPEG
encoding. Media indexing uses original content rather than filenames, generated
descriptions or transcripts.

Audio extensions are `wav`, `mp3`, `m4a`, `aac`, `flac`, `aiff`, `aif` and `caf`;
decoding depends on macOS AVAudioFile support for the actual format. Input sample
rates must be between 8 and 384 kHz, with at most 32 channels. PDF pages and audio
segments are processed in order. More than 100,000 pages or segments fails the
resource guard instead of silently indexing only part of a material.

Original hashes are verified before using file bytes. Damaged, locked or
unsupported materials fail individually while other indexing work continues.
Failed materials leave the index in a partial state. The same material revision
can be retried by a later indexing request after a 60-second cooldown. Video
indexing, OCR and transcription are not implemented.

## Ranking

Vector retrieval scans batches of 256 inside a read snapshot. The service checks
current page or material revisions, content, archive state and requested filters
before returning candidates, excluding stale indexed versions.

Page search combines keyword candidates with the top 20 semantic page candidates
using reciprocal rank fusion (RRF).

Material search uses the following sequence:

1. Retrieve up to 20 material candidates from each text, image and audio ranking.
2. Form their union and retain each material's highest-cosine match as evidence.
3. Sort that union by cosine in the model's shared normalized vector space and
   retain the global top 20 semantic candidates.
4. Combine those semantic candidates with keyword candidates using RRF.

The retained semantic match supplies the original page or audio interval shown
in a result. Ranking across modalities uses cosine; RRF combines keyword and
semantic retrieval. Similarity scores indicate proximity to a query, not whether
a material answers it.

Active page and material searches use semantic retrieval where available.
Archived searches and the legacy source-search interface retain keyword behavior.
While indexing is incomplete, results report warming or partial coverage rather
than treating missing vectors as evidence that relevant content is absent.
Inference failures preserve keyword fallback.

## Worker and memory lifecycle

One private worker per library owns the inference runtime. A startup lock and
worker lease prevent the app and MCP clients from launching duplicate workers.
Clients connect through a Unix socket in a directory restricted to the current
user. The inference runtime listens on loopback and uses a generated API key.

Indexing loads one passage or media chunk at a time. Foreground query requests
are served between those operations. An empty library does not require model
startup.

During media indexing, the runtime uses an 8,192-token context and the multimodal
projector. Queries reuse that runtime while indexing is active. Once the queue
drains, the worker stops the multimodal runtime and starts a text-query runtime
with a 2,048-token context and no projector. The worker owns at most one inference
process at a time. After 60 seconds without foreground or indexing work, it stops
the runtime and exits.

## Cache and evidence contracts

The derived cache lives outside the authoritative wiki database and can be
rebuilt. Its namespace includes model and projector hashes and an input
preparation version; entry keys also include exact prepared input. A change to
assets or preprocessing must use a new namespace, keeping incompatible vectors
separate. Cache updates do not replace originals, extraction snapshots, citations
or page history.

Visual and audio matches retain a location in the original. Opening a PDF match
navigates to its page; opening an audio match positions the native player at the
segment start without autoplay. These locations do not supply OCR text, a
transcript or a verified quotation. Exact citation validation remains tied to
the original hash and the preserved extraction page.

The implementation is in
[SemanticSearch.swift](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumCore/SemanticSearch.swift),
[SemanticMedia.swift](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumCore/SemanticMedia.swift)
and [EmbeddingService.swift](https://github.com/KimEJ/Galpium/blob/main/Sources/GalpiumCore/EmbeddingService.swift).
See [architecture](ARCHITECTURE.md) for the library and write contracts.
