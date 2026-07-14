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
# Example: Compiling the recommended DistilBERT model (Ungated, highly recommended, fastest compilation)
./scripts/compile_prompt_guard.py --model fmops/distilbert-prompt-injection

# Example: Compiling Meta's official Llama Prompt Guard 86M
# Note: You must first run `huggingface-cli login` and accept Meta's license on HF
./scripts/compile_prompt_guard.py --model meta-llama/Prompt-Guard-86M
```

## Installing the Model

Once the script finishes, it will produce a `.mlmodelc.zip` file in your directory (e.g. `distilbert-prompt-injection.mlmodelc.zip`).

**To use it in Iris:**

1. Host this `.zip` file somewhere accessible (like a GitHub Release, AWS S3, or your own web server).
2. Open Iris and navigate to **Settings -> Models**.
3. Under the **Advanced Prompt Injection Protection** section, paste the direct URL to your `.zip` file into the "CoreML .zip URL or Path" field.
4. Click **Download CoreML Model**. 

Iris will automatically download the archive, unzip it into `~/.iris/models/`, and load it into the `CoreMLEvaluator` instantly. Any future evaluations will be hardware-accelerated and run locally on your Mac!
