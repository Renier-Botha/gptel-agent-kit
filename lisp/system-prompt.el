;;; system-prompt.el --- Point the model at its own README -*- lexical-binding: t; -*-

;; Appends a short pointer to gptel's system prompt telling the model
;; where its full tool documentation and the define_tool contract
;; live, so the main prompt stays short.

(require 'gptel)

(defconst gptel-agent-readme-path
  (expand-file-name "../README.md"
                     (file-name-directory (or load-file-name buffer-file-name)))
  "Path to the gptel agent's self-documentation.")

(defconst gptel-agent-capability-note
  (format "\n\nThis Emacs session has extra tools available beyond the \
usual gptel tool-calling: reading/writing buffers and files, `@ref` \
expansion in prompts, and the ability to define brand-new tools for \
yourself at runtime via `define_tool` (persists across restarts). \
Full documentation, the exact `define_tool` contract, and the list of \
existing tools are in %s -- read it with `read_file` before creating a \
new tool, or any time you're unsure what capabilities you have. \
\n\nTool-use policy: strongly prefer the built-in read tools \
(read_file, read_buffer, list_directory, list_project_files, \
grep_project) over `run_shell_command` equivalents like `find`, `cat`, \
`ls`, or `grep` -- they're cheaper, don't bloat the transcript, and \
are always allowed without confirmation. Only reach for the shell \
when a task genuinely needs it (running tests/builds, git, etc). If \
an `@ref` in the user's prompt did not expand (you'll see an inline \
\"[gptel-agent: could not resolve ...]\" marker instead of the \
file's contents), that means resolution failed relative to the \
project root or default-directory shown in the marker -- it does NOT \
mean the file doesn't exist. Use list_directory/grep_project/ \
list_project_files first to relocate it (it's often just in a \
different worktree or a path relative to a different root) before \
falling back to a broad shell search."
          gptel-agent-readme-path)
  "Short pointer appended to gptel's system prompt.")

(defun gptel-agent--append-once (base note)
  "Return BASE with NOTE appended, unless it's already present."
  (if (and (stringp base) (string-search note base))
      base
    (concat (or base "") note)))

;; Update the `default' directive so future directive resets/switches
;; back to it still include the note.
(when-let* ((cell (assq 'default gptel-directives)))
  (setcdr cell (gptel-agent--append-once (cdr cell) gptel-agent-capability-note)))

;; Update the live value too, so it takes effect immediately.
(setq-default gptel-system-prompt
              (gptel-agent--append-once (default-value 'gptel-system-prompt)
                                        gptel-agent-capability-note))

(provide 'gptel-agent-system-prompt)
;;; system-prompt.el ends here
