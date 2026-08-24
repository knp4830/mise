# Terminal & Git Log

> **What this file is:** every command used on this project, what it does, and what its flags mean. Written for looking things up six weeks from now.
> **How to use it:** when you run something new, add it. When you forget something, `Cmd+F` it.
> **Rule:** if you paste a command you don't understand, look it up here or ask before running it. That habit is the difference between learning the terminal and being afraid of it.

---

## The first error, and what it taught

```
kevinp@Kevins-MacBook-Air ~ % mkdir ~/code/mise && cd ~/code/mise
mkdir: /Users/kevinp/code: No such file or directory
```

**What happened:** `mkdir` creates *one* directory. It will not create missing parents. You asked it to make `mise` inside `code`, but `code` didn't exist, so it gave up — and it named the folder it couldn't find (`/Users/kevinp/code`), which is the useful part of the message.

**The fix:**

```bash
mkdir -p ~/code/mise && cd ~/code/mise
```

`-p` = *parents*. Create every missing folder in the path, and don't error if they already exist.

**The second attempt:**

```
mkdir: /project: No such file or directory
```

Different problem. The leading `/` means "start at the root of the entire filesystem," alongside `/System`, `/Applications`, `/Users`. macOS won't let you write there without `sudo`, and you shouldn't want to — your projects belong in your home folder.

**Reading error messages is a skill.** These two look similar and have different causes. `mkdir` told you exactly which path it couldn't find in both cases; the difference was *why*. Most terminal errors are this legible once you slow down and read the whole line.

---

## Paths — the thing that trips everyone up first

| Symbol | Means | Example |
|---|---|---|
| `/` | Root of the whole filesystem | `/Users/kevinp/code` |
| `~` | Your home folder (`/Users/kevinp`) | `~/code/mise` |
| `.` | The folder you're in right now | `./scripts/seed.sh` |
| `..` | One folder up | `cd ..` |
| `-` | The folder you were in before | `cd -` |

**Absolute path** starts with `/` or `~` and works from anywhere: `~/code/mise/src`.
**Relative path** starts from where you currently are: `src/app`.

Your prompt tells you where you are. `kevinp@Kevins-MacBook-Air ~ %` — that `~` is the current folder. Inside the project it becomes `mise %`. When a command misbehaves, check that first: **you are very often just in the wrong directory.**

```bash
pwd    # print working directory — "where am I?"
```

---

## Navigating and looking around

```bash
pwd                  # where am I
ls                   # list files here
ls -la               # list ALL files (-a, including dotfiles like .env) in long form (-l)
cd ~/code/mise       # go somewhere
cd ..                # up one level
cd -                 # back to the previous folder
open .               # macOS: open the current folder in Finder
code .               # open the current folder in VSCode
```

`ls -la` is the one to memorize. Files starting with `.` are hidden by default — and `.env`, `.gitignore`, and `.github/` are all files you'll care about. Plain `ls` won't show them.

**Flags combine.** `-la` is `-l -a`. This is true of most commands.

---

## Creating, moving, deleting

```bash
mkdir docs                    # make a directory
mkdir -p src/lib/queries      # make it and any missing parents
touch README.md               # create an empty file (or update its timestamp)
cp file.txt backup.txt        # copy
cp -r docs/ docs-backup/      # copy a folder (-r = recursive, into subfolders)
mv old.txt new.txt            # rename
mv file.txt docs/             # move into a folder
rm file.txt                   # delete a file
rm -rf node_modules           # delete a folder and everything in it
```

> **`rm -rf` has no undo and no Trash.** There is no recovery. Before running it, read the path out loud. `rm -rf ~/code` would delete this entire project silently. It's a normal, necessary command — just never run it on autopilot.

---

## Reading files

```bash
cat CLAUDE.md            # dump the whole file
head -20 package.json    # first 20 lines
tail -20 error.log       # last 20 lines
less BUILD-PLAN.md       # scrollable viewer — arrows to move, q to quit
```

`less` is what you want for anything long. `q` quits — worth knowing before you get stuck in it.

---

## Chaining commands

| Operator | Means |
|---|---|
| `&&` | Run the next command **only if** the previous one succeeded |
| `;` | Run the next command regardless |
| `\|` | Pipe: send the first command's output into the second |
| `>` | Write output to a file, **overwriting** it |
| `>>` | Append output to a file |

```bash
mkdir -p ~/code/mise && cd ~/code/mise   # only cd if mkdir worked
ls -la | grep ".env"                     # list files, keep only lines containing .env
echo "node_modules" >> .gitignore        # append a line
```

`&&` is the one you'll use constantly, and using it instead of `;` is a small safety habit: if the first command fails, the second doesn't run against the wrong state.

---

## Git — the ~12 commands that are 95% of daily use

```bash
git init -b main             # start a repo, name the first branch "main"
git status                   # what's changed — run this constantly
git add file.txt             # stage one file
git add -A                   # stage everything changed
git commit -m "message"      # save a snapshot of what's staged
git log --oneline -10        # last 10 commits, one line each
git diff                     # what changed but isn't staged yet
git diff --staged            # what's staged and about to be committed
```

**Branches:**

```bash
git branch                        # list branches, * marks current
git checkout -b feat/m0-3-scaffold  # create a branch AND switch to it
git checkout main                 # switch to an existing branch
git branch -d feat/old-thing      # delete a merged branch
```

**Talking to GitHub:**

```bash
git push -u origin main      # push, and remember this remote (-u, first time only)
git push                     # after that, just this
git pull                     # fetch and merge others' changes (or your own from another machine)
git remote -v                # which GitHub repo is this connected to
```

**The mental model:** git has three places a change can live.

```
working directory  →  staging area  →  commit history
   (you edit)          (git add)        (git commit)
```

`git status` shows you which stage everything is in. When git confuses you, run `git status` first — it usually tells you what to do next, in plain English.

**Undo, in increasing severity:**

```bash
git restore file.txt              # discard uncommitted changes to a file
git restore --staged file.txt     # unstage, but keep the changes
git commit --amend                # fix the most recent commit message
git reset --soft HEAD~1           # undo last commit, KEEP the changes staged
git reset --hard HEAD~1           # undo last commit, DESTROY the changes
```

> `--hard` discards work permanently. Reach for `--soft` first — it's almost always what you actually wanted.

---

## GitHub CLI (`gh`)

```bash
gh auth status                    # am I logged in
gh auth login                     # log in
gh repo create mise --private --source=. --remote=origin
gh repo view --web                # open this repo in the browser

gh issue list                     # open issues
gh issue list --milestone "Phase 0 — Foundations"
gh issue create --title "..." --body "..." --label "type:feature"

gh pr create --fill               # open a PR using the branch's commits
gh pr view --web                  # open the PR in the browser to read your own diff
gh pr merge --squash --delete-branch
```

`gh` exists so you don't context-switch to the browser for routine things. The one exception, deliberately: **read your own diff in the browser before merging.** The web view makes problems visible in a way the terminal doesn't.

---

## Node and pnpm

```bash
node -v                    # check Node version (need 20+)
pnpm -v                    # check pnpm is installed
npm i -g pnpm              # install pnpm globally

pnpm install               # install everything in package.json
pnpm add zod               # add a dependency
pnpm add -D vitest         # add a DEV dependency (-D: build/test only, not shipped)
pnpm remove zod            # remove one

pnpm dev                   # start the dev server
pnpm build                 # production build
pnpm lint                  # run the linter
```

**`-D` matters.** Dev dependencies (test runners, type definitions, linters) don't ship to production. Putting them in the wrong place bloats your deploy.

---

## When you're stuck

```bash
man mkdir        # full manual — q to quit
mkdir --help     # shorter summary (some macOS commands don't support this)
which node       # where is this command installed
```

`Ctrl+C` cancels a running command. `Ctrl+A` jumps to the start of the line, `Ctrl+E` to the end. Up-arrow cycles through your history.

```bash
history | grep mkdir     # find a command you ran before but can't remember
```

---

## Running log — commands used on this project, in order

| Date | Command | Why | What I learned |
|---|---|---|---|
| 2026-08-24 | `mkdir ~/code/mise` | Create project folder | **Failed.** `mkdir` won't create parent folders |
| 2026-08-24 | `mkdir /project/mise` | Retry | **Failed.** `/` is the filesystem root, needs sudo, wrong place anyway |
| 2026-08-24 | `mkdir ~p ~/code/mise` | Typo for `-p` | `~name` means that user's home dir, so zsh looked for a user called `p`. The shell expands `~`, `*`, `$` *before* running the command |
| 2026-08-24 | `mkdir -p ~/code/mise && cd ~/code/mise` | Create it properly | `-p` creates parents; `&&` only runs `cd` if `mkdir` succeeded |
| 2026-08-24 | `gh api repos/{owner}/{repo}/milestones -f title="..." --silent` | Create 8 milestones | **Failed 8× with 422.** `--silent` hid the reason. Never use it on an unproven command. 8 identical failures = systemic cause, not a data problem |
| | | | |

*Append a row every time you run something new. Keep the failures — those are the rows you'll actually come back and read.*
