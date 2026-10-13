# Third-party notices

Galpium's application code, plugin and documentation are licensed under
[Apache License 2.0](LICENSE). Bundled model and runtime components retain the
licenses listed below.

| Component | Distributed revision | License and attribution |
| --- | --- | --- |
| EmbeddingGemma 2 model and image/audio projector | Google source revision `914f7f89142e33e77833254d9c9b90c3cef7303b` | Google DeepMind; [Apache License 2.0](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2) |
| Q8_0 GGUF conversion | ggml-org revision `bfcd298762cc34d0357ece5ebdd31791a3a374d8` | [ggml-org EmbeddingGemma 2 GGUF](https://huggingface.co/ggml-org/embeddinggemma-2-GGUF); distributed without changes to the weights |
| llama.cpp | `b11468`, commit `b7dafa01e5f375c3010fb24b61a67329f957426a` | MIT, with the accompanying vendor notices |

Complete licenses, copyright notices, conversion attribution and the model card
are bundled under `Galpium.app/Contents/Resources/Embedding/licenses/`. They can
also be opened from **Settings → Model and open-source licenses**.
Asset revisions and checksums are recorded in `scripts/prepare-embedding.py`.
Model weights and runtime binaries are not committed to this source repository.

The earlier Galpium 0.0.1 distribution used EmbeddingGemma 300M under the Gemma
Terms of Use. Its accompanying terms remain applicable to those assets; the
current model license does not relicense an earlier distribution.
