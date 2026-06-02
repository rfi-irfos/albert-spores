# albert-spores

**albert.** is a self-growing language model trained collectively — across dedicated GPUs, laptops, and everything in between. This repo is where contributors worldwide submit checkpoint fragments called *spores*. Every accepted spore gets blended into the live model at the next training cycle.

No GPU required. No ML background required. If your machine can run Python, it can help albert. grow.

Watch the model in your browser right now: **[ternlang.com/talk](https://ternlang.com/talk)**

---

## Setup

Two commands. Takes about 10 minutes on first run (Rust compilation).

```bash
git clone https://github.com/eriirfos-eng/albert-spores ~/projects/albert-spores
bash ~/projects/albert-spores/install.sh
```

Then open a fresh terminal — three commands are now available everywhere.

---

## Contributing

```bash
albert-train
```

That's it. `albert-train` runs CPU training, opens a live dashboard in your browser, and tells you when your epoch is done. Stop any time with Ctrl-C — your last completed epoch is already saved locally.

When you're ready to share:

```bash
albert-spore
```

Packages your checkpoint and pushes it to the pool. You'll need `gh auth login` once (GitHub CLI) to push — the installer will prompt you if it's not set up.

---

## Commands

| Command | What it does |
|---|---|
| `albert-train` | CPU training — opens live dashboard, Ctrl-C to stop |
| `albert-test` | Chat with albert. locally, run benchmarks |
| `albert-spore` | Push your latest checkpoint to the colony |

---

## How it works

You run `albert-train` on your CPU. After each epoch, your checkpoint is saved locally. When you run `albert-spore`, it's packaged and pushed here. The main training loop — running on GPU — ingests accepted spores at every epoch boundary and blends them into the live model weights.

The more contributors, the more routing diversity. A ThinkPad in Budapest and a MacBook in Lagos teach albert. things the GPU alone never sees.

---

## Fitness gate

Spores are accepted when `loss < main_best + 1.0`. The margin is intentionally wide — CPU-trained checkpoints are welcome even when raw loss is far from the GPU frontier. The model benefits from routing diversity across varied hardware regardless of absolute loss.

---

## What happens at ingestion

The SporeManager blends accepted spores into the live model at epoch boundaries with α = 0.08:

- F32 weights: `w = 0.92 · w_main + 0.08 · w_spore`
- Ternary weights: blended, then re-ternarized at ±0.04

Your checkpoint shifts the balance without overriding it. You can't break anything.

---

## Spore structure

```
spores/
  {contributor}/
    {YYYY-MM-DD}/
      spore_ep{N}_{loss}.safetensors    — checkpoint weights
      spore_ep{N}_{loss}.json           — metadata (epoch, loss, architecture)
```

---

## Troubleshooting

**`albert-train` says "train_bible not built"**
Re-run the installer:
```bash
bash ~/projects/albert-spores/install.sh
```

**No spore pushed / push failed**
```bash
gh auth login   # one-time GitHub auth
albert-spore    # retry push
```

**Push rejected / diverged branches**
```bash
git -C ~/projects/albert-spores pull --rebase
albert-spore
```

**Dashboard shows red / stale**
Use the full URL printed by `albert-train` — it includes timing parameters tuned for CPU speed.

**`albert-spore` says "no training checkpoint found"**
Let `albert-train` run until you see the first epoch summary line, then Ctrl-C. That's your first spore.

**`albert-spore` says "already committed"**
Train another epoch to get a new spore with updated weights.

---

## Updating

```bash
git -C ~/projects/albert-spores pull && bash ~/projects/albert-spores/install.sh
```

Safe to re-run at any time.

## Contributors

Built by the RFI-IRFOS core team — see [CONTRIBUTORS.md](CONTRIBUTORS.md).
