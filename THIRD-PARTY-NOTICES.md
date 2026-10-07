# Third-party components

The Apache 2.0 license covers Galpium's application code, plugin and documentation.
It does not replace the licenses of components bundled in the macOS app.

| Component | Version | License and attribution |
| --- | --- | --- |
| EmbeddingGemma 2 | Google source revision `914f7f89142e33e77833254d9c9b90c3cef7303b`; Q8_0 text model and Q8_0 image/audio projector | Google DeepMind; [Apache License 2.0](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2) |
| GGUF conversion | ggml-org revision `bfcd298762cc34d0357ece5ebdd31791a3a374d8`; SHA-256 values in `scripts/prepare-embedding.py` | [EmbeddingGemma 2 conversion](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF), bundled without additional changes |
| llama.cpp | `b11468`, commit `b7dafa01e5f375c3010fb24b61a67329f957426a` | MIT, including its bundled vendor notices |

EmbeddingGemma 2 is distributed under Apache 2.0. The bundled license, original
copyright notices and GGUF conversion attribution are retained with the model.
Consult Google's [model card](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2)
for the model's intended use and limitations.

The immutable Galpium 0.0.1 release bundled the earlier EmbeddingGemma 300M model
under the Gemma Terms of Use. That release's accompanying notices still apply to
its model bytes; this update does not relicense old release assets.

The app contains complete terms, notices and licenses under
`Contents/Resources/Embedding/licenses/`. They are available from
**Settings → Model and open-source licenses**. The build verifies the model,
projector and runtime SHA-256 values before packaging. Model weights and runtime binaries are
release assets, not part of this source repository.
