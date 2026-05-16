#!/usr/bin/env bash
# albert-spores installer
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
BINARY="$TIS/albert-moe-13/target/release/moe-test"

printf "\n${B}albert-spores installer${R}\n"
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
    if [ "$OS" = "Darwin" ]; then need_brew; brew install python3; else sudo apt-get install -y python3 python3-pip -q; fi
fi

# pip
python3 -m pip --version &>/dev/null || {
    [ "$OS" = "Darwin" ] && { need_brew; brew install python3; } || sudo apt-get install -y python3-pip -q
}
ok "pip $(python3 -m pip --version | awk '{print $2}')"

# git
command -v git &>/dev/null && ok "git $(git --version | awk '{print $3}')" || {
    [ "$OS" = "Darwin" ] && xcode-select --install 2>/dev/null || sudo apt-get install -y git -q
}

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

# Modal
if python3 -c "import modal" 2>/dev/null; then
    ok "modal $(python3 -c 'import modal; print(modal.__version__)' 2>/dev/null || echo installed)"
else
    printf "  installing modal...\n"
    python3 -m pip install modal -q && ok "modal installed"
fi

# ── 2. Repos ───────────────────────────────────────────────────────────────────
step "2/6" "Repositories"

mkdir -p "$PROJECTS"

if [ -d "$TIS/.git" ]; then
    ok "TIS repo present"
    git -C "$TIS" pull --ff-only -q 2>/dev/null && ok "pulled latest" || warn "local changes — skipping pull"
else
    printf "  cloning TIS repo...\n"
    git clone -q https://github.com/eriirfos-eng/ternary-intelligence-stack.git "$TIS"
    ok "TIS repo cloned to $TIS"
fi

if [ -d "$SPORES/.git" ]; then
    ok "albert-spores present at $SPORES"
else
    printf "  cloning albert-spores...\n"
    if gh repo clone eriirfos-eng/albert-spores "$SPORES" 2>/dev/null; then
        ok "albert-spores cloned"
    else
        warn "albert-spores clone failed — run 'gh auth login' first, then re-run this installer"
    fi
fi

# ── 3. Build moe-test ─────────────────────────────────────────────────────────
step "3/6" "moe-test binary (one-time build, ~5-10 min)"

export PATH="$HOME/.cargo/bin:$PATH"

if [ -f "$BINARY" ]; then
    ok "moe-test binary present"
else
    printf "  compiling moe-test...\n"
    cargo build --release \
        --manifest-path "$TIS/albert-moe-13/moe-test/Cargo.toml" \
        --target-dir "$TIS/albert-moe-13/target" \
        2>&1 | grep -E "^(error|   Compiling moe|    Finished)"
    ok "moe-test compiled"
fi

# ── 4. Commands ────────────────────────────────────────────────────────────────
step "4/6" "Installing commands to ~/bin"

mkdir -p "$BIN"

# albert-train
cat > "$BIN/albert-train" << 'HEREDOC'
#!/usr/bin/env python3
"""albert-train — start GPU training on Modal + local dashboard"""
import os, sys, subprocess, threading, signal, time, webbrowser, re, glob

R="\033[0m"; BLUE="\033[38;5;33m"; LBLUE="\033[38;5;75m"; GREEN="\033[1;92m"
YELLOW="\033[93m"; CYAN="\033[96m"; RED="\033[91m"; DIM="\033[2m"; BOLD="\033[1;94m"

def colorize(line):
    s = line.rstrip("\n")
    if re.match(r"^(GRAD|DIV|DIVF32|DIVGRAD|DIVWMD|DIVV2)\b", s): return ""
    if re.match(r"^Epoch \d+ \(Global \d+\), Batch \d+: loss = ", s): return ""
    if re.match(r"\[\d{2}:\d{2}:\d{2}\] Epoch", s): return f"{BLUE}{s}{R}\n"
    if "=== Epoch" in s and "done" in s: return f"{GREEN}{s}{R}\n"
    if s.startswith("EPOCH_SUMMARY") or s.startswith("[evolution]") or s.startswith("[net2net]"):
        return f"{GREEN}{s}{R}\n"
    if s.startswith("WALD:") or s.startswith("[lb]") or s.startswith("[divloss]"):
        return f"{YELLOW}{s}{R}\n"
    if s.startswith("[modal]") or s.startswith("[albert"): return f"{CYAN}{s}{R}\n"
    if "Gate reset:" in s or "symmetry break" in s or "gate-diversity" in s: return f"{DIM}{s}{R}\n"
    if s.startswith("   Compiling") or s.startswith("   Finished") or s.startswith("warning:") or s.startswith("Downloading"):
        return f"{DIM}{s}{R}\n"
    if "error" in s.lower() and ("Error:" in s or "error[" in s or "ERRO" in s): return f"{RED}{s}{R}\n"
    if s.startswith("[ttlfreeze]") or s.startswith("[flags]") or s.startswith("---"): return f"{LBLUE}{s}{R}\n"
    return line

PROJECT  = os.path.expanduser("~/projects/ternary-intelligence-stack/albert-moe-13")
MODAL_PY = os.path.join(PROJECT, "train_modal.py")
LOG      = os.path.expanduser("~/.albert/training.log")
DASH_SRV = os.path.join(PROJECT, "dashboard", "run_server.py")
MERGE_PY = os.path.join(PROJECT, "scripts", "merge_batch_history.py")
os.makedirs(os.path.expanduser("~/.albert"), exist_ok=True)

if len(sys.argv) > 1 and sys.argv[1] == "pull":
    os.chdir(PROJECT)
    sys.exit(subprocess.run([sys.executable, MODAL_PY, "pull"]).returncode)

detach     = "--detach"     in sys.argv
no_browser = "--no-browser" in sys.argv
skip_merge = "--no-merge"   in sys.argv

def preflight_merge():
    downloads = os.path.expanduser("~/Desktop/Downloads/albert_full_*.csv")
    if not glob.glob(downloads): return
    print(f"{CYAN}[albert-train] merging batch history from Downloads...{R}")
    result = subprocess.run([sys.executable, MERGE_PY], cwd=PROJECT, capture_output=True, text=True)
    new_pts = "0"
    for line in result.stdout.splitlines():
        if "Total unique points" in line:
            print(f"{CYAN}[albert-train] {line.strip()}{R}")
            m = re.search(r"\+([0-9,]+)\s*\)", line)
            if m: new_pts = m.group(1).replace(",", "")
    if result.returncode != 0:
        print(f"{RED}[albert-train] merge script error:{R}\n{result.stderr[:400]}")
        return
    if int(new_pts) == 0:
        print(f"{CYAN}[albert-train] batch_history up to date{R}")
        return
    subprocess.run(["git", "add", "dashboard/batch_history.csv"], cwd=PROJECT)
    msg = f"data: patch batch_history +{new_pts} points from Downloads CSVs"
    r = subprocess.run(["git", "commit", "-m", msg], cwd=PROJECT, capture_output=True, text=True)
    if r.returncode == 0:
        print(f"{GREEN}[albert-train] committed batch_history (+{new_pts} pts){R}")
        push = subprocess.run(["git", "push"], cwd=PROJECT, capture_output=True, text=True)
        if push.returncode == 0: print(f"{GREEN}[albert-train] pushed to GitHub{R}")
        else: print(f"{YELLOW}[albert-train] push failed: {push.stderr.strip()[:120]}{R}")

print(f"{BOLD}--- Starting Albert Training Orchestrator (v3.0 · Modal GPU) ---{R}")
if not skip_merge: preflight_merge()

server_proc = subprocess.Popen(
    [sys.executable, DASH_SRV], cwd=os.path.join(PROJECT, "dashboard"),
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
print(f"Dashboard server started (PID: {server_proc.pid})")
time.sleep(0.5)

if not no_browser:
    print("Opening dashboard in Firefox...")
    webbrowser.get("firefox").open("http://localhost:8888/dashboard/")

modal_cmd = ["modal", "run"]
if detach: modal_cmd.append("--detach")
modal_cmd.append(MODAL_PY)
print(f"Training started via Modal ({'detached' if detach else 'streaming'})")

open(LOG, "w").close()
log_f = open(LOG, "a")

train_proc = subprocess.Popen(
    modal_cmd, cwd=PROJECT,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
)

def stream():
    global log_f
    for line in train_proc.stdout:
        if line.startswith("RUN_START "):
            log_f.close(); open(LOG, "w").close(); log_f = open(LOG, "a")
            print(f"{CYAN}[albert-train] fresh run detected — log flushed{R}")
        sys.stdout.write(colorize(line)); sys.stdout.flush()
        log_f.write(line); log_f.flush()

stream_thread = threading.Thread(target=stream, daemon=True)
stream_thread.start()

def on_sigint(sig, frame):
    print("\nStopping orchestrator...")
    train_proc.send_signal(signal.SIGINT)

signal.signal(signal.SIGINT, on_sigint)
train_proc.wait()
stream_thread.join(timeout=3)
log_f.close()

print(f"\n{BOLD}--- Training run ended ---{R}")
print(f"{CYAN}Dashboard still live at http://localhost:8888/dashboard/{R}")
print(f"{CYAN}Run  albert-train pull  to sync checkpoint.{R}")
try:
    server_proc.wait()
except KeyboardInterrupt:
    server_proc.terminate()
HEREDOC

# albert-test
cat > "$BIN/albert-test" << 'HEREDOC'
#!/usr/bin/env python3
"""albert-test — interactive TUI for albert. (chat, /bench, /export)"""
import os, sys, subprocess

PROJECT = os.path.expanduser("~/projects/ternary-intelligence-stack/albert-moe-13")
BINARY  = os.path.join(PROJECT, "target", "release", "moe-test")

def build():
    print("[albert-test] building moe-test ...")
    r = subprocess.run(["cargo", "build", "--release", "-p", "moe-test"], cwd=PROJECT)
    if r.returncode != 0:
        print("[albert-test] build failed"); sys.exit(r.returncode)
    print("[albert-test] build OK")

force_rebuild = "--rebuild" in sys.argv
if force_rebuild or not os.path.exists(BINARY):
    build()

args = [a for a in sys.argv[1:] if a != "--rebuild"]
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

# ── 6. ~/.albert ───────────────────────────────────────────────────────────────
step "6/6" "Runtime directories"

mkdir -p "$HOME/.albert"
ok "~/.albert created"

# ── Done ───────────────────────────────────────────────────────────────────────
printf "\n${G}Installation complete.${R}\n\n"
printf "Next steps:\n"
printf "  ${B}gh auth login${R}    — GitHub auth (opens browser)\n"
printf "  ${B}modal setup${R}      — Modal GPU auth (opens browser, needed for albert-train)\n"
printf "\nThen open a fresh terminal and run:\n"
printf "  ${B}albert-test${R}      — chat with albert.\n"
printf "  ${B}albert-train${R}     — train on Modal GPU\n"
printf "  ${B}albert-spore${R}     — submit your checkpoint\n\n"
