#!/usr/bin/env python3
"""
Konvertuje pre-trained ECAPA-TDNN speaker embedder do CoreML formátu
pro použití v Nova iOS app.

Model: speechbrain/spkrec-ecapa-voxceleb
Output: 192-dim speaker embedding per 3 sekundy audio (16kHz mono)

Runtime: Mac M4 (Neural Engine), bude běžet na iPhone 15 Pro Max ANE.
"""

import os
import sys
import numpy as np
import torch
import coremltools as ct
from speechbrain.inference.speaker import EncoderClassifier

print("=" * 60)
print("Nova Voice ID — ECAPA-TDNN → CoreML converter")
print("=" * 60)

# Pracovní složka
os.makedirs("pretrained_models", exist_ok=True)

# 1) Stáhni pre-trained ECAPA-TDNN
print("\n[1/4] Loading pre-trained ECAPA-TDNN from HuggingFace...")
classifier = EncoderClassifier.from_hparams(
    source="speechbrain/spkrec-ecapa-voxceleb",
    savedir="pretrained_models/spkrec-ecapa-voxceleb",
    run_opts={"device": "cpu"}
)
classifier.eval()
print("   ✅ Model loaded")

# 2) Extrahuj samotný embedding encoder
embedding_model = classifier.mods.embedding_model
embedding_model.eval()

# 3) Trace přes fixní vstup
# ECAPA-TDNN očekává mel spektrogram jako vstup (batch, frames, mel_bins=80)
# Pro 3 sekundy audio @ 16kHz → ~300 frames
print("\n[2/4] Tracing model with TorchScript...")

# ECAPA-TDNN z speechbrain potřebuje nejdřív mel features.
# Vytvoříme wrapper který bere raw waveform a uvnitř dělá feature extraction.
class ECAPAWrapper(torch.nn.Module):
    def __init__(self, sb_classifier):
        super().__init__()
        self.compute_features = sb_classifier.mods.compute_features
        self.mean_var_norm = sb_classifier.mods.mean_var_norm
        self.embedding_model = sb_classifier.mods.embedding_model

    def forward(self, wavs):
        # wavs shape: (batch=1, samples=48000) pro 3s @ 16kHz
        # Compute mel features
        feats = self.compute_features(wavs)  # (1, frames, 80)
        # Mean/var normalization
        wav_lens = torch.ones(wavs.shape[0], device=wavs.device)
        feats = self.mean_var_norm(feats, wav_lens)
        # Get embedding
        embedding = self.embedding_model(feats, wav_lens)  # (1, 1, 192)
        # Squeeze to (1, 192)
        return embedding.squeeze(1)

wrapper = ECAPAWrapper(classifier)
wrapper.eval()

# Fixní vstupní velikost: 3 sekundy @ 16kHz = 48000 samples
example_input = torch.randn(1, 48000)
with torch.no_grad():
    traced = torch.jit.trace(wrapper, example_input)
print("   ✅ Model traced")

# Test prediction
with torch.no_grad():
    test_out = wrapper(example_input)
print(f"   ✅ Test output shape: {test_out.shape} (expected [1, 192])")
assert test_out.shape == (1, 192), f"Unexpected shape: {test_out.shape}"

# 4) Konverze do CoreML
print("\n[3/4] Converting to CoreML (Neural Engine target)...")

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="audio", shape=(1, 48000), dtype=np.float32)],
    outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
    minimum_deployment_target=ct.target.iOS17,
    compute_units=ct.ComputeUnit.CPU_AND_NE,  # Neural Engine + CPU fallback
    convert_to="mlprogram",  # ML Program = modern format pro A14+
)

mlmodel.short_description = "ECAPA-TDNN speaker embedder (192-dim) for Nova voice verification"
mlmodel.author = "FxLooper (based on speechbrain/spkrec-ecapa-voxceleb)"
mlmodel.license = "Apache 2.0"
mlmodel.version = "1.0"

# 5) Save
output_path = "SpeakerEmbedder.mlpackage"
print(f"\n[4/4] Saving to {output_path}...")
mlmodel.save(output_path)
print(f"   ✅ Saved")

# Verify
print("\n" + "=" * 60)
print("VERIFICATION")
print("=" * 60)
print(f"Input:  audio (1, 48000) float32  — 3 sec @ 16kHz mono")
print(f"Output: embedding (1, 192) float32 — speaker vector")
print(f"File:   {os.path.abspath(output_path)}")
print()
print("Next step: Drag SpeakerEmbedder.mlpackage into Xcode Nova target.")
