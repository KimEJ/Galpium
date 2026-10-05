# Third-party components

The Apache 2.0 license covers Galpium's application code, plugin and documentation.
It does not replace the licenses of components bundled in the macOS app.

| Component | Version | License and attribution |
| --- | --- | --- |
| EmbeddingGemma | 300M, Q8_0 GGUF | Google DeepMind; [Gemma Terms of Use](https://ai.google.dev/gemma/terms) and [Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy) |
| GGUF conversion | ggml-org revision `0f741b5a6585bd53aeb15cd1372c56f2a0f65e12` | Q8_0 conversion of EmbeddingGemma, bundled without additional changes |
| llama.cpp | `b11371`, commit `99b95488cac0f00ce3f05af113a8c1e287753f87` | MIT, including its bundled vendor notices |

Model use and redistribution are subject to the Gemma Terms and the use
restrictions incorporated in section 3.2. These conditions apply to the model
component. Galpium source code remains licensed under Apache 2.0.

The app contains complete terms, notices and licenses under
`Contents/Resources/Embedding/licenses/`. They are available from
**Settings → Model and open-source licenses**. The build verifies the model and
runtime SHA-256 values before packaging. Model weights and runtime binaries are
release assets, not part of this source repository.
