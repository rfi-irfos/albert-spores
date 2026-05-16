#!/usr/bin/env bash
# albert-spores installer — CPU-only contributor setup
# Run after cloning this repo:
#   gh repo clone eriirfos-eng/albert-spores ~/projects/albert-spores
#   bash ~/projects/albert-spores/install.sh
set -e

B="\033[1;34m"; G="\033[1;32m"; Y="\033[93m"; R="\033[0m"
step() { printf "\n${B}[%s]${R} %s\n" "$1" "$2"; }
ok()   { printf "  ${G}ok${R}  %s\n" "$1"; }
warn() { printf "  ${Y}!!${R}  %s\n" "$1"; }

OS=$(uname -s); ARCH=$(uname -m)
PROJECTS="$HOME/projects"
TIS="$PROJECTS/ternary-intelligence-stack"
SPORES="$PROJECTS/albert-spores"
BIN="$HOME/bin"
MOE_TEST="$TIS/albert-moe-13/target/release/moe-test"
TRAIN_BIBLE="$TIS/albert-moe-13/target/release/train_bible"

printf "\n${B}albert-spores installer${R}  (CPU-only contributor build)\n"
printf "platform: %s-%s\n" "$OS" "$ARCH"

# ── 1. System deps ─────────────────────────────────────────────────────────────
step "1/6" "System dependencies"

need_brew() {
    command -v brew &>/dev/null && return 0
    warn "Homebrew not found — install from https://brew.sh then re-run this script"
    exit 1
}

# python3
if command -v python3 &>/dev/null; then
    ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
    if [ "$OS" = "Darwin" ]; then need_brew; brew install python3
    else sudo apt-get install -y python3 python3-pip -q; fi
fi

# git
if command -v git &>/dev/null; then
    ok "git $(git --version | awk '{print $3}')"
else
    if [ "$OS" = "Darwin" ]; then xcode-select --install 2>/dev/null || true
    else sudo apt-get install -y git -q; fi
fi

# gh CLI
if command -v gh &>/dev/null; then
    ok "gh $(gh --version | head -1 | awk '{print $3}')"
else
    printf "  installing gh CLI...\n"
    if [ "$OS" = "Darwin" ]; then
        need_brew; brew install gh
    else
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y gh -q
    fi
    ok "gh installed"
fi

# Rust
if command -v cargo &>/dev/null; then
    ok "cargo $(cargo --version | awk '{print $2}')"
else
    printf "  installing Rust (one-time, ~2 min)...\n"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    export PATH="$HOME/.cargo/bin:$PATH"
    ok "cargo installed"
fi

export PATH="$HOME/.cargo/bin:$PATH"

# ── 2. Repos ───────────────────────────────────────────────────────────────────
step "2/6" "Repositories"

mkdir -p "$PROJECTS"

if [ -d "$TIS/.git" ]; then
    ok "TIS repo present"
    git -C "$TIS" pull --ff-only -q 2>/dev/null && ok "pulled latest" || warn "local changes — skipping pull"
else
    printf "  cloning TIS repo (~55 MB)...\n"
    git clone -q https://github.com/eriirfos-eng/ternary-intelligence-stack.git "$TIS"
    ok "TIS repo cloned"
fi

if [ -d "$SPORES/.git" ]; then
    ok "albert-spores present"
else
    printf "  cloning albert-spores...\n"
    if gh repo clone eriirfos-eng/albert-spores "$SPORES" 2>/dev/null; then
        ok "albert-spores cloned"
    else
        warn "albert-spores clone failed — run 'gh auth login' first, then re-run this installer"
    fi
fi

# ── 3. Build binaries ──────────────────────────────────────────────────────────
step "3/6" "Building binaries (one-time, ~10-15 min)"

MOE_DIR="$TIS/albert-moe-13"

if [ -f "$MOE_TEST" ] && [ -f "$TRAIN_BIBLE" ]; then
    ok "moe-test and train_bible already built"
else
    printf "  compiling moe-test and train_bible from workspace...\n"
    # Both crates live in the albert-moe-13 workspace — build them together
    cargo build --release \
        --manifest-path "$MOE_DIR/Cargo.toml" \
        --bin moe-test \
        --bin train_bible \
        --target-dir "$MOE_DIR/target" \
        2>&1 | grep -E "^(error|   Compiling (moe-test|train_bible|moe-llm)|    Finished)"
    ok "moe-test built"
    ok "train_bible built"
fi

# ── 4. Commands ────────────────────────────────────────────────────────────────
step "4/6" "Installing commands to ~/bin"

mkdir -p "$BIN"

# albert-train — runs train_bible locally on CPU
cat > "$BIN/albert-train" << 'HEREDOC'
#!/usr/bin/env python3
"""albert-train — run albert. training locally on CPU"""
import os, sys, subprocess, signal, re, time, webbrowser

B="\033[38;5;33m"; G="\033[1;92m"; Y="\033[93m"; C="\033[96m"
D="\033[2m"; LB="\033[38;5;75m"; RD="\033[91m"; R="\033[0m"; BD="\033[1;94m"

def colorize(line):
    s = line.rstrip("\n")
    if re.match(r"^(GRAD|DIV|DIVF32|DIVGRAD|DIVWMD|DIVV2)\b", s): return ""
    if re.match(r"^Epoch \d+ \(Global \d+\), Batch \d+: loss = ", s): return ""
    if re.match(r"\[\d{2}:\d{2}:\d{2}\] Epoch", s): return f"{B}{s}{R}\n"
    if "=== Epoch" in s and "done" in s: return f"{G}{s}{R}\n"
    if s.startswith("EPOCH_SUMMARY") or s.startswith("[evolution]") or s.startswith("[net2net]"):
        return f"{G}{s}{R}\n"
    if s.startswith("WALD:") or s.startswith("[lb]"): return f"{Y}{s}{R}\n"
    if s.startswith("[albert"): return f"{C}{s}{R}\n"
    if "Gate reset:" in s or "symmetry break" in s: return f"{D}{s}{R}\n"
    if s.startswith("   Compiling") or s.startswith("    Finished"): return f"{D}{s}{R}\n"
    if "error" in s.lower() and ("Error:" in s or "error[" in s): return f"{RD}{s}{R}\n"
    if s.startswith("[ttlfreeze]") or s.startswith("---"): return f"{LB}{s}{R}\n"
    return line

PROJECT  = os.path.expanduser("~/projects/ternary-intelligence-stack/albert-moe-13")
BINARY   = os.path.join(PROJECT, "target", "release", "train_bible")
DASH_SRV = os.path.join(PROJECT, "dashboard", "run_server.py")
LOG      = os.path.expanduser("~/.albert/training.log")
os.makedirs(os.path.expanduser("~/.albert"), exist_ok=True)

if not os.path.exists(BINARY):
    print("[albert-train] train_bible not built — run: bash ~/projects/albert-spores/install.sh")
    sys.exit(1)

no_browser = "--no-browser" in sys.argv
extra = [a for a in sys.argv[1:] if a != "--no-browser"]
cmd = [BINARY, f"--root={PROJECT}"] + extra

print(f"{BD}--- albert. CPU training ---{R}")
print(f"log: {LOG}  |  Ctrl-C to stop, then run  albert-spore  to submit\n")

# Start dashboard server if available
if os.path.exists(DASH_SRV):
    server = subprocess.Popen(
        [sys.executable, DASH_SRV],
        cwd=os.path.join(PROJECT, "dashboard"),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(0.5)
    if not no_browser:
        webbrowser.open("http://localhost:8888/dashboard/?poll_ms=2000&stale_s=300")  # CPU-safe thresholds
    print(f"Dashboard: http://localhost:8888/dashboard/?poll_ms=2000&stale_s=300\n")

open(LOG, "w").close()
log_f = open(LOG, "a")

proc = subprocess.Popen(
    cmd, cwd=PROJECT,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
)

def on_sigint(sig, frame):
    print("\n[albert-train] stopping...")
    proc.send_signal(signal.SIGINT)

signal.signal(signal.SIGINT, on_sigint)

for line in proc.stdout:
    out = colorize(line)
    if out:
        sys.stdout.write(out)
        sys.stdout.flush()
    log_f.write(line)
    log_f.flush()

proc.wait()
log_f.close()
print(f"\n{BD}--- Training stopped ---{R}")
print("Run  albert-spore  to submit your checkpoint.")
HEREDOC

# albert-test
cat > "$BIN/albert-test" << 'HEREDOC'
#!/usr/bin/env python3
"""albert-test — interactive TUI for albert. (chat, /bench, /export)"""
import os, sys, subprocess

PROJECT = os.path.expanduser("~/projects/ternary-intelligence-stack/albert-moe-13")
BINARY  = os.path.join(PROJECT, "target", "release", "moe-test")

if not os.path.exists(BINARY):
    print("[albert-test] moe-test not built — run: bash ~/projects/albert-spores/install.sh")
    sys.exit(1)

args = [a for a in sys.argv[1:]]
os.chdir(PROJECT)
sys.exit(subprocess.run([BINARY] + args).returncode)
HEREDOC

# albert-spore
cat > "$BIN/albert-spore" << 'HEREDOC'
#!/usr/bin/env python3
"""albert-spore — package and submit checkpoint to the albert. spore pool"""
import os, sys, subprocess

PROJECT = os.path.expanduser("~/projects/ternary-intelligence-stack/albert-moe-13")
SPORES  = os.path.expanduser("~/projects/albert-spores")
SCRIPT  = os.path.join(PROJECT, "scripts", "produce_spore.py")

if not os.path.exists(SCRIPT):
    print("[albert-spore] TIS repo not found at ~/projects/ternary-intelligence-stack")
    print("[albert-spore] Re-run: bash ~/projects/albert-spores/install.sh")
    sys.exit(1)

if not os.path.isdir(os.path.join(SPORES, ".git")):
    print("[albert-spore] albert-spores repo not found at ~/projects/albert-spores")
    print("[albert-spore] Run: gh repo clone eriirfos-eng/albert-spores ~/projects/albert-spores")
    sys.exit(1)

os.chdir(PROJECT)
sys.exit(subprocess.run(
    [sys.executable, SCRIPT, "--spores-repo", SPORES] + sys.argv[1:]
).returncode)
HEREDOC

chmod +x "$BIN/albert-train" "$BIN/albert-test" "$BIN/albert-spore"
ok "albert-train, albert-test, albert-spore written to $BIN"

# ── 5. PATH ────────────────────────────────────────────────────────────────────
step "5/6" "PATH configuration"

PATH_LINE='export PATH="$HOME/bin:$HOME/.cargo/bin:$PATH"'
for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$RC" ] || continue
    if grep -qF 'HOME/bin' "$RC" 2>/dev/null; then
        ok "$RC already includes ~/bin"
    else
        printf '\n%s\n' "$PATH_LINE" >> "$RC"
        ok "added ~/bin to $RC"
    fi
done

# ── 6. Runtime dirs ────────────────────────────────────────────────────────────
step "6/6" "Runtime directories"

mkdir -p "$HOME/.albert"
ok "~/.albert created"

# ── Done ───────────────────────────────────────────────────────────────────────
printf "\n${G}Installation complete.${R}\n\n"
printf "Open a fresh terminal. All three commands are ready:\n\n"
printf "  ${B}albert-test${R}     — chat with albert.\n"
printf "  ${B}albert-train${R}    — train on CPU, opens dashboard in browser (Ctrl-C to stop)\n"
printf "  ${B}albert-spore${R}    — submit your checkpoint to the colony\n\n"
