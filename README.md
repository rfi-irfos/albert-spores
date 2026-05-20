# albert-spores

**albert.** is a self-growing language model trained collectively — across dedicated GPUs, laptops, and everything in between. This repo is where contributors worldwide submit checkpoint fragments called *spores*. Every accepted spore gets blended into the live model at the next training cycle.

No GPU required. No ML background required. If your machine can run Python, it can help albert. grow.

---

## How it works

You run `albert-train` on your CPU. After each 30-batch epoch, your checkpoint is automatically packaged and pushed here as a spore. The main training loop — running on GPU — ingests accepted spores at every epoch boundary and blends them into the live model weights. Your contribution shifts albert. in a small but real direction.

The more contributors, the more routing diversity. A ThinkPad in Budapest and a MacBook in Lagos teach albert. things the GPU alone never sees.

---

## Setup

One time, takes about 10 minutes on first run (Rust compilation).

### 1. Authenticate GitHub

```bash
gh auth login
```

Opens a browser, 30 seconds. If `gh` is not installed, get it at [cli.github.com](https://cli.github.com).

### 2. Clone and install

```bash
gh repo clone eriirfos-eng/albert-spores ~/projects/albert-spores
bash ~/projects/albert-spores/install.sh
```

Installs all dependencies (git-lfs, Rust, gh CLI), builds the training binary, and adds three commands to `~/bin`. Subsequent runs are instant.

### 3. Open a fresh terminal

`~/bin` is now on your PATH. All three commands are available everywhere.

---

## Contributing

```bash
albert-train
```

That's it. `albert-train` runs CPU training, opens a live dashboard in your browser, and **automatically pushes a spore after every epoch**. Stop any time with Ctrl-C — your last completed epoch is already in the pool.

Your GitHub login (from `gh auth`) is your contributor identity. No extra flags or config needed.

---

## Commands

| Command | What it does |
|---|---|
| `albert-train` | CPU training — auto-pushes a spore after each epoch, opens dashboard |
| `albert-test` | Chat with albert. locally, run benchmarks |
| `albert-spore` | Manually push your latest checkpoint without training more |

---

## Fitness gate

Spores are accepted when `loss < main_best + 1.0`. The margin is intentionally wide — CPU-trained checkpoints are welcome even when raw loss is far from the GPU frontier. The model benefits from routing diversity across varied hardware regardless of absolute loss.

---

## What happens at ingestion

The SporeManager blends accepted spores into the live model at epoch boundaries with α = 0.08:

- F32 weights: `w = 0.92 · w_main + 0.08 · w_spore`
- Ternary weights: blended, then re-ternarized at ±0.04

Your checkpoint shifts the balance without overriding it. The main model wins all sign-flip contests. You can't break anything.

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
Re-run the installer — it builds the binary automatically:
```bash
bash ~/projects/albert-spores/install.sh
```

**No spore pushed after epoch**
Check the output for `[albert-train] auto-spore`. If it says `TIMEOUT`, your connection was too slow for the upload window. Run `albert-spore` manually after training to retry:
```bash
albert-spore
```

**Push rejected / diverged branches**
The repo received new spores while yours was uploading. Run:
```bash
git -C ~/projects/albert-spores pull --rebase
```
Then run `albert-spore` again.

**Dashboard shows red / stale**
Use the full URL printed by `albert-train` in the terminal — it includes timing parameters tuned for CPU training speed.

**`albert-spore` says "no training checkpoint found"**
`albert-train` saves a checkpoint after the first complete epoch. Let it run until you see the first epoch summary line, then you can stop.

**`albert-spore` says "already committed"**
Your checkpoint is already in the pool from a previous run. Train another epoch to get a new spore with updated weights.

---

## Updating

```bash
git -C ~/projects/albert-spores pull --rebase && bash ~/projects/albert-spores/install.sh
```

Safe to re-run at any time. Re-running install after a pull picks up any changes to the training binary or commands.
