# albert-spores

Federated checkpoint pool for **albert.** — a self-growing ternary mixture-of-experts language model trained by [RFI-IRFOS](https://ternlang.com).

When you submit a spore, your local checkpoint gets blended into the main model on the next training cycle. Contributions from diverse hardware and corpora improve routing diversity across the colony.

---

## Quickstart

Tested on Linux (x86\_64, ARM64) and macOS.

### Step 1 — clone and install

```bash
gh repo clone eriirfos-eng/albert-spores ~/projects/albert-spores
bash ~/projects/albert-spores/install.sh
```

This installs: dependencies (git, Rust, Python 3, Modal), the TIS training repo, the moe-test binary, and the three commands below into `~/bin`. Build time: ~10 min on first run (Rust compilation). Subsequent installs are instant.

### Step 2 — authenticate

```bash
gh auth login     # GitHub — opens browser
modal setup       # Modal GPU — opens browser, needed for albert-train
```

Open a fresh terminal. Done.

---

## Commands

| Command | What it does |
|---------|-------------|
| `albert-test` | Local TUI — chat with albert., run benchmarks, export results |
| `albert-train` | Start GPU training on Modal, stream log to local dashboard |
| `albert-train pull` | Download latest checkpoint from Modal volume |
| `albert-spore` | Package your checkpoint and push it to this repo |

---

## Contributing a spore

```bash
albert-train pull          # sync latest checkpoint from Modal
albert-spore               # auto-detects your GitHub login
albert-spore --name lucia  # override contributor name
```

Your spore lands in `spores/{name}/{YYYY-MM-DD}/`. The main training loop ingests it automatically if it passes the fitness gate.

---

## Fitness gate

Spores are accepted when `loss_at_production < main_best_loss + 1.0`. The margin is intentionally wide — CPU-trained spores around loss 11 are welcome. Routing diversity from varied hardware matters even when raw loss doesn't match GPU speed.

---

## Spore structure

```
spores/
  {contributor}/
    {YYYY-MM-DD}/
      spore_ep{N}_{loss}.safetensors    — checkpoint weights
      spore_ep{N}_{loss}.json           — metadata (epoch, loss, architecture, hardware)
```

---

## What happens at ingestion

The SporeManager (`moe-llm-core/src/spore.rs`) blends accepted spores into the live model at epoch boundaries with α = 0.08:

- F32 tensors: `w = 0.92 · w_main + 0.08 · w_spore`
- Ternary weights: same blend, then re-ternarized at ±0.04

The main model wins all sign-flip contests. Your spore shifts the balance without overriding it.

---

## Re-running the installer

```bash
bash ~/projects/albert-spores/install.sh
```

Safe to re-run — existing repos are pulled, not re-cloned.
