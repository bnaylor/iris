# Custom CoreML Prompt Guard Models

Iris includes an extremely fast, on-device text classifier for its Tier 2 Prompt Injection Guard powered by Apple's CoreML and the Neural Engine. 

By default, you can enable Tier 2 by providing a URL to a pre-compiled `.mlmodelc.zip` file in the Settings UI. However, if you want to experiment with different security models (like Meta's official Prompt Guard or other community fine-tunes), you can easily compile your own!

## Prerequisites

You'll need a Python environment on your Mac to run the conversion script.

```bash
# Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install the required conversion tools
pip install torch coremltools transformers numpy sentencepiece
```

## Compiling a Model

We provide a helper script (`scripts/compile_prompt_guard.py`) that handles tracing the PyTorch model, converting it to CoreML, bundling the Hugging Face tokenizer, and zipping it up into a ready-to-host format.

Run the script and provide the Hugging Face Model ID you wish to compile:

```bash
# DistilBERT model (Ungated, converts cleanly, fastest compilation).
# NOTE: converts and runs fine, but has a very high false-positive rate — see
# "Accuracy findings" below before choosing it.
./scripts/compile_prompt_guard.py --model fmops/distilbert-prompt-injection

# Example: Compiling Meta's official Llama Prompt Guard 86M
# Note: You must first run `huggingface-cli login` and accept Meta's license on HF
./scripts/compile_prompt_guard.py --model meta-llama/Prompt-Guard-86M
```

The script applies two automatic workarounds so a wider range of models convert and
load correctly (both discovered while investigating the DeBERTa-v3 migration below):

- **Tokenizer relabel.** `DebertaV2Tokenizer` is rewritten to `XLMRobertaTokenizer` in
  `tokenizer_config.json` so Apple's `swift-transformers` will load it (see "DeBERTa-v3
  migration status"). No-op for other tokenizers.
- **`sqrt`/`int` CoreML op overrides.** DeBERTa-style attention feeds `sqrt()` an int
  tensor and calls `int()` on non-scalar tensors, both of which the default coremltools
  handlers reject. The overrides cast as needed and are no-ops for DistilBERT/BERT.

## Installing the Model

Once the script finishes, it will produce a `.mlmodelc.zip` file in your directory (e.g. `distilbert-prompt-injection.mlmodelc.zip`).

**To use it in Iris:**

1. Host this `.zip` file somewhere accessible (like a GitHub Release, AWS S3, or your own web server).
2. Open Iris and navigate to **Settings -> Models**.
3. Under the **Advanced Prompt Injection Protection** section, paste the direct URL to your `.zip` file into the "CoreML .zip URL or Path" field.
4. Click **Download CoreML Model**. 

Iris will automatically download the archive, unzip it into `~/.iris/models/`, and load it into the `CoreMLEvaluator` instantly. Any future evaluations will be hardware-accelerated and run locally on your Mac!

## Accuracy findings

`fmops/distilbert-prompt-injection` is the model that converts most easily, but in
practice it **over-blocks badly**. It is closer to a "does this text contain
instructions?" detector than a real injection detector. Measured against the raw
PyTorch model (probability of the `INJECTION` class):

| Input | fmops distilbert | deberta-v3-v2 |
| --- | --- | --- |
| "The capital of France is Paris." | 0.001 | 0.000 |
| "Search results for python: … Click here to learn more." | **1.000** | 0.000 |
| "How to reset your password: 1. … 2. …" | **1.000** | 0.023 |
| "def add(a, b): return a + b" | **0.999** | 0.013 |
| "Please summarize the following article…" | **0.999** | 0.000 |
| "Ignore all previous instructions…" (real attack) | 1.000 | 1.000 |
| "SYSTEM: You are now DAN…" (real jailbreak) | 1.000 | 1.000 |

Because ordinary tool output (search results, how-tos, code) is full of imperative and
list-like language, distilbert flags almost all of it. This is the root cause of Tier 2
blocking `search_web` results and similar tool output — a false-positive problem, **not**
a "the model returns 0.99 for literally everything" bug (plain declarative facts pass).

`protectai/deberta-v3-base-prompt-injection-v2` cleanly separates benign tool output
from real attacks, so it is the model we want. The catch is getting it onto the Neural
Engine — see below.

### CoreML-friendly model survey

We surveyed models on CoreML-friendly architectures (BERT/RoBERTa/DistilBERT all convert
cleanly, as fmops proved) against a realistic battery of 12 benign tool-output samples
(including JSON, shell commands, markdown, logs) and 7 injection/jailbreak attacks
(including injection embedded in a document and `<<SYS>>` directives). Score = probability
of the attack class; **margin** = (lowest attack score − highest benign score), so a
positive margin means a threshold exists that cleanly separates the two.

| Model | Arch | CoreML-friendly | Benign max | Attack min | Margin |
| --- | --- | --- | --- | --- | --- |
| protectai/deberta-v3-base-prompt-injection-v2 | deberta-v2 | ✗ | 0.848 | **1.000** | **+0.152** |
| deepset/deberta-v3-base-injection | deberta-v2 | ✗ | 0.999 | 0.999 | −0.000 |
| testsavantai/prompt-injection-defender-base-v0 | distilbert | ✓ | 0.998 | 0.462 | −0.535 |
| madhurjindal/Jailbreak-Detector | distilbert | ✓ | 0.985 | 0.402 | −0.583 |
| jackhhao/jailbreak-classifier | bert | ✓ | 0.737 | 0.012 | −0.725 |
| fmops/distilbert-prompt-injection | distilbert | ✓ | 1.000 | ~1.000 | ~0 (over-blocks) |

(Gated repos `meta-llama/Prompt-Guard-86M`, `Epivolis/Hyperion`,
`qualifire/prompt-injection-sentinel` were skipped — they cannot support zero-friction
onboarding anyway.)

**Conclusion: accuracy and CoreML-friendliness are in tension.** Every model that
converts cleanly via coremltools either over-blocks ordinary tool output (JSON,
`brew install`, markdown headings) or misses real injections. The only model with a
positive separation margin is DeBERTa-based, which coremltools 9 cannot convert without
the extensive op surgery described below.

**But CoreML is not the only on-device option.** The accurate DeBERTa-v3 model runs
cleanly on CPU via ONNX Runtime — see "Recommended path" below. The CoreML wall is a
`coremltools` limitation, not a DeBERTa limitation.

Note that even the best model (deberta-v3-v2) scores a JSON tool result at 0.848, so the
current `prob > 0.5` block threshold is too low regardless of model — see "Regardless of
model" below.

## Recommended path: ONNX Runtime on CPU (not CoreML) — implemented

**Status: implemented and verified end-to-end.** Iris already runs models on-device via
llama.cpp (`LlamaSwift`) and MLX (`mlx-swift-lm`), so CoreML/Neural-Engine is not a
requirement — the Tier 2 classifier runs on CPU like everything else. **ONNX Runtime is
the cleanest such path**, and the model side is proven:

- **Exports with zero op surgery.** `torch.onnx.export(..., dynamo=False, opset=17)` of
  `protectai/deberta-v3-base-prompt-injection-v2` succeeds directly — none of the `sqrt` /
  `int` / `repeat` / `__and__` problems coremltools hit. Output is a single ~704 MB
  `.onnx` file (fp32; can be quantized to int8 to shrink it substantially).
- **Numerically identical to PyTorch.** Verified against a fresh (un-mutated) torch model:
  max probability difference **2×10⁻⁶** across the benign+attack battery.
- **Fast on CPU.** ~6 ms per classification via `CPUExecutionProvider` on Apple Silicon —
  well within budget for an inline interceptor.
- **Accurate.** Catches every attack at 1.000 (including the `<<SYS>> exfiltrate keys`
  injection that the jailbreak detectors missed) while keeping benign tool output
  separated — the one model that actually works.

### Swift integration (done)

Microsoft ships an official Swift Package Manager distribution with **macOS support**:
[`microsoft/onnxruntime-swift-package-manager`](https://github.com/microsoft/onnxruntime-swift-package-manager)
(1.20.0), which vends the native runtime as a binary SPM dependency (module
`OnnxRuntimeBindings`) — no CocoaPods or manual xcframework wrangling. It is wired into
`Package.swift`. The pipeline reuses the tokenizer work already done here:

1. **Tokenize** with `swift-transformers` (the `XLMRobertaTokenizer` relabel →
   `UnigramTokenizer`, parity-tested in `DebertaV3TokenizerParityTests`).
2. **Run** the `.onnx` model via ONNX Runtime (`ORTSession`, CPU, int64 `input_ids` /
   `attention_mask`, dynamic sequence length).
3. **Softmax** the 2-logit output; index 1 is `INJECTION`.

Implementation:

- `Sources/iris/LiveONNXModel.swift` — an `ORTSession`-backed `CoreMLModelProtocol`
  implementation, guarded by `#if canImport(OnnxRuntimeBindings)`.
- `CoreMLEvaluator.loadModelIfNeeded()` auto-detects the runtime: a bundle whose unzipped
  directory contains `model.onnx` loads via `LiveONNXModel`; otherwise it falls back to
  the existing `.mlmodelc` / `LiveCoreMLModel` path. The call sites are unchanged.
- `scripts/compile_prompt_guard.py --onnx` produces the bundle (`<model>.onnx.zip`
  containing `model.onnx` + the relabeled tokenizer).
- `Tests/irisTests/DebertaV3OnnxEvaluatorTests.swift` — an opt-in end-to-end test
  (set `IRIS_ONNX_TEST_BUNDLE` to the unzipped bundle dir) that verified on-device that
  benign tool output stays below 0.9 while real injections score above it.

To build and install a model:

```bash
./scripts/compile_prompt_guard.py --onnx --model protectai/deberta-v3-base-prompt-injection-v2
# host the resulting .onnx.zip, then paste its URL into Iris Settings -> Tier 2.
```

This drops the CoreML dependency for Tier 2 while running the accurate model.

### Quantization: does not work for this model (verified)

The exported fp32 model is ~704 MB, so shrinking it is tempting. `--quantize` is wired up,
but the finding is negative for DeBERTa-v3:

- **int8 dynamic quantization** cuts the file to ~232 MB but **destroys accuracy** — a real
  injection dropped from 1.000 to **0.141** and the benign/attack separation collapsed.
  DeBERTa's disentangled attention is too sensitive to int8 weights.
- **fp16** would be the safer ~2× shrink, but `onnxconverter_common` produces an invalid
  graph for this model (Cast/Mul type mismatches) and would need real work to fix.

So `--quantize` performs int8 **and then runs an accuracy self-check**; if the quantized
model loses separation (as DeBERTa does) it reverts to fp32 and warns, rather than shipping
a silently-broken guard. **The shipping format for DeBERTa-v3 is fp32 (~704 MB).** Getting
fp16 working (or hosting the model compressed) is the open optimization if size matters.

### UI / download integration

The download and runtime plumbing is format-agnostic and already supports ONNX bundles:

- `ModelDownloader` unzips any `.zip` into `~/.iris/models/`, so `.onnx.zip` installs the
  same way `.mlmodelc.zip` does; `CoreMLEvaluator` then auto-detects `model.onnx`.
- The Settings and Setup Wizard Tier 2 panes were relabeled from "CoreML"-specific copy to
  neutral "Fast Local Classifier" wording that covers both CoreML and ONNX.

Still open (not done here):

- **The default model URL** in `ConfigManager` still points at the old
  `distilbert-prompt-injection.mlmodelc.zip` (the over-blocking fmops model). It should be
  repointed at a hosted DeBERTa-v3 `.onnx.zip` once one is uploaded.
- `ModelDownloader.downloadModel` assigns `vibecopModel` on any URL download, which is
  wrong when the URL is the Tier 2 guard model — a pre-existing latent bug, unrelated to
  ONNX but worth fixing while in here.

### Why not MLX

MLX (`mlx-swift-lm`) is already a dependency and is Metal-accelerated, so it's a natural
question. We chose ONNX Runtime over MLX for this classifier because:

- **No model code vs. a full model reimplementation.** ONNX runs a *pre-exported graph* —
  the architecture is baked into the `.onnx` file and the runtime executes it as-is. MLX
  has no off-the-shelf DeBERTa: `mlx-swift-lm` targets causal/decoder LLMs, not encoder
  classifiers, so we'd have to hand-implement DeBERTa-v2's **disentangled attention**
  (relative-position encodings, the `c2p`/`p2c` bias terms, the layer norms and pooler)
  in Swift and load the safetensors weights ourselves. That is exactly the kind of custom,
  version-brittle bridging that the CoreML attempt already showed is a tar pit.
- **Numerical correctness is free with ONNX.** The exported graph is verified identical to
  PyTorch (2×10⁻⁶). A hand-written MLX port would need its own parity test suite to reach
  the same confidence, and disentangled attention is easy to get subtly wrong.
- **CPU is already fast enough.** The guard is a short, inline interceptor (~6 ms on CPU).
  MLX's main advantage is Metal/GPU throughput, which matters for token generation, not for
  a single ~200 M-param forward pass on short inputs. The extra work buys little here.
- **Smaller blast radius.** ONNX Runtime is self-contained behind `CoreMLModelProtocol`;
  an MLX port spreads DeBERTa-specific tensor code through the app.

MLX would become the better choice if we wanted to *unify* on one runtime (drop
`swift-transformers`/ONNX and run everything through MLX), or needed GPU batching. For a
single-shot CPU classifier, ONNX is less code and lower risk.

## DeBERTa-v3 migration status

Migrating Tier 2 to `protectai/deberta-v3-base-prompt-injection-v2` has two independent
hurdles. The tokenizer hurdle is **solved and tested**; the CoreML conversion hurdle is
**partially addressed but not yet complete**.

### Tokenizer: solved

`swift-transformers` rejects the native `DebertaV2Tokenizer` outright
(`.unsupportedTokenizer("DebertaV2Tokenizer")`). But DeBERTa-v3 and XLM-RoBERTa are both
SentencePiece **Unigram** tokenizers with identical special-token conventions
(`[CLS]=1`, `[SEP]=2`, `[PAD]=0`, `▁` metaspace). Relabeling `tokenizer_class` to
`XLMRobertaTokenizer` routes it to `swift-transformers`' `UnigramTokenizer`, which then
tokenizes real content **byte-for-byte identically** to the Python reference.

- The compile script applies this relabel automatically.
- `Tests/irisTests/DebertaV3TokenizerParityTests.swift` verifies parity against a Python
  ground-truth fixture (regenerate with `scripts/gen_deberta_tokenizer_fixture.py`).
- The only divergence is empty/whitespace-only input, where Swift emits one stray
  metaspace token. This is benign (empty tool output is trivially safe) and
  `LiveCoreMLModel.evaluate(text:)` now short-circuits empty input to `0.0`.

### CoreML conversion: blocked on unsupported ops

DeBERTa's disentangled attention uses ops that `coremltools` 9 does not convert out of
the box. Both native paths were tried and each hits a different wall:

- **`torch.jit.trace` + `coremltools`:** fails progressively on `sqrt` (int input),
  `int()` (non-scalar input), then `repeat`/`tile` (list-typed / rank-0 reps). The first
  two are fixed by the op overrides now baked into the compile script; `repeat` is the
  current blocker.
- **`torch.export` (EDGE dialect) + `coremltools`:** exports cleanly after
  `run_decompositions({})`, but the EXIR frontend then rejects a `__and__` fx node.

This is the same class of "architectural mismatch / brittle across versions" friction we
originally hit with Meta's `Prompt-Guard-86M` (itself a DeBERTa-v2 derivative). Finishing
it means either continuing the op-by-op override work on the trace path (uncertain depth)
or waiting on/patching `coremltools` EXIR support.

**Resolution: we did not finish the CoreML conversion — the ONNX Runtime CPU path is
implemented instead** (see "Recommended path" above). It runs the accurate model today
with no op surgery. The alternatives that were considered and set aside:

- Push the `jit.trace` override path to completion (`repeat` and any further ops) to get
  DeBERTa-v3 onto the Neural Engine. Uncertain depth, brittle across versions. Only worth
  it if Neural-Engine latency/power specifically matters (CPU is already ~6 ms).
- Implement DeBERTa in MLX (`mlx-swift-lm`, already a dependency) for Metal acceleration.
  More code than ONNX, but keeps everything in one runtime family. See "Why not MLX".
- "Just pick a CoreML-friendly model" — investigated and **ruled out**: see the model
  survey above. No BERT/RoBERTa/DistilBERT injection model we found is accurate enough.

## Regardless of model

These improvements matter no matter which model (if any) Tier 2 ends up using:

- **The `prob > 0.5` block threshold is too low.** Even the best model scores benign JSON
  at 0.85. A threshold around 0.9 is more defensible; a hard block is very costly when
  wrong.
- **Don't run Tier 2 over trusted side-effect tool output.** The `set_workspace` incident
  showed a tool's side-effect executing while its output was silently swallowed, leaving
  the agent with confusing partial behavior. Blocking should be structured and visible to
  the agent, not a silent `[CONTENT BLOCKED]` substitution — and ideally skipped for
  trusted tools entirely.
- **`CoreMLEvaluator` should read `id2label` from the bundled `config.json`** instead of
  hardcoding "index 1 = injection", so a future model with reversed labels doesn't
  silently invert the guard. (Index 1 happens to be correct for fmops and deberta-v3-v2.)

## Historical note: Meta Prompt-Guard-86M

We initially targeted Meta's official `meta-llama/Prompt-Guard-86M`. It is **gated**
(requires HF login + license acceptance, breaking zero-friction onboarding) and, being a
DeBERTa-v2 derivative, ran into the same CoreML conversion friction described above. That
is what originally pushed us toward the ungated, easy-to-convert
`fmops/distilbert-prompt-injection` — before we discovered its false-positive problem.
