# gptel-agent-kit

A self-contained extension layer on top of [gptel](https://github.com/karthink/gptel) that turns it into a proper coding agent inside Emacs: file/buffer read & write tools, `@ref`/`@skill` context expansion, skills, and the ability for the model to **write and load brand-new tools for itself at runtime**.

It's a thin, reviewable layer: everything it does is plain tool calls gptel already supports, plus some Elisp glue. Nothing here talks to any API directly; it just configures what tools/behavior gptel has to work with.

## What it gives gptel

- **Read tools** — `read_file`, `read_buffer`, `list_directory`,
  `list_project_files`, `grep_project`, `list_open_buffers`. Always on,
  never require confirmation.
- **Write tools** — `write_file`, `write_buffer`, `edit_buffer`,
  `save_buffer`. On by default, confirm-gated per call.
- **`@ref` expansion** — write `@init.el` or `@src/foo.py` in your
  prompt and it's expanded to that buffer's/file's contents before
  being sent. `C-c C-f` gives you a
  `find-file`-style picker that inserts the reference for you.
- **Skills** — picks up `<skill>/SKILL.md` files
  (project-local `.agents/skills/` or `~/.agents/skills/`). Reference
  one with `@skill-name` or browse/insert with `C-c C-a`.
- **Misc utilities** — `diff_buffer`, `revert_buffer`, `delete_file`,
  `rename_file`, `byte_compile_check`.
- **Self-authoring** — a `define_tool` meta-tool
  that lets the model write a new Elisp tool, have it syntax-checked,
  loaded into the running session, and persisted to disk so it
  survives an Emacs restart.

Every write, including self-authored tools, requires your explicit
confirmation by default (there's a buffer-local "approve all" escape
hatch for bursts of scaffolding work, see below).

## How it works

```
your-config/                 <- wherever you clone/symlink this repo
├── core/                    <- this repo. Hand-written, reviewed like normal code.
│   ├── init.el              entry point, loads everything in lisp/
│   ├── README.md            this file
│   └── lisp/
│       ├── tools-read.el       read-only tools
│       ├── tools-edit.el       write tools
│       ├── tools-exec.el       run_shell_command / eval_elisp
│       ├── context-at-refs.el  @ref expansion in prompts
│       ├── skills.el           pickup of ~/.agents/skills/ SKILL.md files
│       ├── meta-tool.el        the define_tool self-authoring mechanism
│       ├── tools-misc.el       misc generic utility tools
│       ├── system-prompt.el    wires this README into gptel's system prompt
│       └── tool-display.el     nicer minibuffer/echo display of tool calls
└── tools/                   <- NOT hand-written. Only ever written by define_tool.
                                Each file here is a tool the model gave itself.
```

`core/` is this repo: generic, publishable mechanism. `tools/` is
meant to be a *separate*, personal/local directory (its own git repo
if you like) — it's where the model's self-authored tools accumulate
over time, so a `git diff` there shows exactly what you've let the
assistant give itself. Don't hand-edit files in it.

Everything loads through a single entry point, `core/init.el`, which:

1. defines `gptel-agent-tools-dir` (defaults to `../tools/` next to
   this repo) and creates it if missing,
2. loads each hand-written module in dependency order,
3. loads every `.el` file already in `tools/` so previously
   self-authored tools come back after a restart.

### The self-authoring loop

The model calls `define_tool` with a name, description, a `lambda`
body, and a gptel `:args` spec. `meta-tool.el`:

1. validates the tool name and syntax-checks both Lisp fragments
   *before* writing anything,
2. writes `tools/<name>.el` (a `gptel-make-tool` registration
   generated from a fixed template — the model never writes that part
   itself),
3. loads it into the running Emacs session immediately, so it's
   callable later in the same conversation,
4. leaves it in `tools/` to auto-load on every future startup.

Nothing runs unsandboxed-but-invisibly: every new tool call still goes
through gptel's normal confirmation UI unless you (or the model,
per-tool, at author time) explicitly set `confirm: false`, and every
line of every self-authored tool lands in a git-tracked file you can
review or roll back.

## Installing in a Doom Emacs config

This is intentionally decoupled from your gptel *backend* config
(API host, auth, model choice) — that stuff stays in
`~/.config/doom/config.el` exactly as it is today. This repo only adds
*agent behavior* on top.

1. Clone it somewhere, e.g.:

   ```sh
   git clone https://github.com/<you>/gptel-agent-kit ~/.config/gptel/core
   ```

2. Make sure `gptel` itself is installed via your `init.el` or within your `packages.el`:

   ```elisp
   ;; ~/.config/doom/packages.el
   (package! gptel)
   ```

3. In `~/.config/doom/config.el`, after your normal `(use-package! gptel ...)`
   block that sets up the backend/auth, add:

   ```elisp
   (let ((init (expand-file-name "~/.config/gptel/core/init.el")))
     (when (file-exists-p init) (load init)))
   ```

4. `doom sync` (only needed if you added the `package!` line) and
   restart/reload Doom.

That's it — `M-x gptel` (or your usual gptel entry point) now has the
extra tools available. Useful commands to know about:

- `gptel-agent-insert-file-ref` (`C-c C-f`) — insert an `@file` ref
- `gptel-agent-insert-skill` (`C-c C-a`) — insert an `@skill` ref
- `gptel-agent-enable-write-tools` / `-disable-write-tools`
- `gptel-agent-enable-meta-tools` / `-disable-meta-tools`
- `gptel-agent-approve-all-enable` / `-disable` — buffer-local, skips
  *all* confirmations (not just this package's) for a burst of work

No separate `tools/` directory ships with this repo — it's created
empty on first load and fills up with whatever tools you and the model
build together.
