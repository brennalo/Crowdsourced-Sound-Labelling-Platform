"""
Lightweight CNN for binary audio classification on mel spectrograms.

Input:  (batch, 1, n_mels=64, time_frames)  — single channel, like grayscale image
Output: (batch, num_classes)                 — raw logits (softmax applied at inference)

Architecture: 4 conv blocks with BatchNorm + MaxPool, then global average pool + FC head.
Chosen over heavier models (ResNet, EfficientNet) because:
- Dataset is small (<10k clips initially)
- 3s mel spectrograms are low-resolution inputs (64 x ~130 frames)
- Needs to fit in Cloud Run Job CPU-only environment
- Export to ONNX is straightforward with no exotic ops
"""

import torch
import torch.nn as nn


class ConvBlock(nn.Module):
    def __init__(self, in_channels: int, out_channels: int, kernel_size: int = 3, pool_size: int = 2):
        super().__init__()
        self.block = nn.Sequential(
            nn.Conv2d(in_channels, out_channels, kernel_size=kernel_size, padding=kernel_size // 2),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True),
            nn.Conv2d(out_channels, out_channels, kernel_size=kernel_size, padding=kernel_size // 2),
            nn.BatchNorm2d(out_channels),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(kernel_size=pool_size),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.block(x)


class ForestSoundCNN(nn.Module):
    def __init__(self, num_classes: int = 2, dropout: float = 0.3):
        super().__init__()

        self.features = nn.Sequential(
            ConvBlock(1, 16),    # (B, 1, 64, T)  → (B, 16, 32, T/2)
            ConvBlock(16, 32),   # (B, 16, 32, T/2) → (B, 32, 16, T/4)
            ConvBlock(32, 64),   # (B, 32, 16, T/4) → (B, 64, 8, T/8)
            ConvBlock(64, 128),  # (B, 64, 8, T/8) → (B, 128, 4, T/16)
        )

        # Global average pooling collapses spatial dims → (B, 128)
        self.global_pool = nn.AdaptiveAvgPool2d((1, 1))

        self.classifier = nn.Sequential(
            nn.Dropout(dropout),
            nn.Linear(128, 64),
            nn.ReLU(inplace=True),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.features(x)
        x = self.global_pool(x)
        x = x.view(x.size(0), -1)  # flatten
        return self.classifier(x)


def build_model(num_classes: int = 2) -> ForestSoundCNN:
    return ForestSoundCNN(num_classes=num_classes)


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


if __name__ == "__main__":
    model = build_model()
    dummy = torch.randn(4, 1, 64, 130)  # batch=4, 3s @ 22050Hz → ~130 frames
    out = model(dummy)
    print(f"Output shape: {out.shape}")
    print(f"Parameters: {count_parameters(model):,}")
