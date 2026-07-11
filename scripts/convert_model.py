#!/usr/bin/env python3
import os
import argparse
from pathlib import Path
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import coremltools as ct

def main():
    parser = argparse.ArgumentParser(description="Convert a Hugging Face prompt injection classifier to CoreML")
    parser.add_argument("--model", type=str, default="protectai/deberta-v3-base-prompt-injection-v2",
                        help="Hugging Face model ID")
    parser.add_argument("--seq-len", type=int, default=512, help="Sequence length for the model")
    args = parser.parse_args()

    print(f"Loading tokenizer and model for {args.model}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    model = AutoModelForSequenceClassification.from_pretrained(args.model)
    model.eval()

    # Create dummy inputs for tracing
    print("Tracing model with PyTorch JIT...")
    dummy_input = "This is a test prompt to trace the model."
    inputs = tokenizer(dummy_input, return_tensors="pt", max_length=args.seq_len, padding="max_length", truncation=True)
    
    input_ids = inputs["input_ids"]
    attention_mask = inputs["attention_mask"]
    
    # Trace the model
    with torch.no_grad():
        traced_model = torch.jit.trace(model, (input_ids, attention_mask), strict=False)

    print("Converting to CoreML MLPackage...")
    # Define CoreML inputs
    coreml_inputs = [
        ct.TensorType(name="input_ids", shape=input_ids.shape, dtype=ct.converters.mil.input_types.Int32),
        ct.TensorType(name="attention_mask", shape=attention_mask.shape, dtype=ct.converters.mil.input_types.Int32)
    ]
    
    mlmodel = ct.convert(
        traced_model,
        inputs=coreml_inputs,
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16
    )

    mlmodel.author = "Iris Agent Harness"
    mlmodel.short_description = f"Prompt Injection Classifier converted from {args.model}"
    
    output_dir = Path.home() / ".iris" / "models"
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "InjectionClassifier.mlpackage"
    
    mlmodel.save(str(output_path))
    
    print(f"✅ Success! CoreML model saved to: {output_path}")
    print("Iris Tier 2 prompt injection guard is now ready to use this model locally via ANE/GPU.")

if __name__ == "__main__":
    main()
