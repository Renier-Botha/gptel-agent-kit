;;; system-prompt.el --- Point the model at its own README -*- lexical-binding: t; -*-

;; Appends a short pointer to gptel's system prompt telling the model
;; where its full tool documentation and the define_tool contract
;; live, so the main prompt stays short.

(require 'gptel)

(defconst gptel-agent-readme-path
  (expand-file-name "readme.org"
                     (file-name-directory (or load-file-name buffer-file-name)))
  "Path to the gptel agent's self-documentation.")

(defconst gptel-agent-capability-note
  (format "\n\nThis Emacs session has extra tools available beyond the \
usual gptel tool-calling: reading/writing buffers and files, `@ref` \
expansion in prompts, and the ability to define brand-new tools for \
yourself at runtime via `define_tool` (persists across restarts). \
Full documentation, the exact `define_tool` contract, and the list of \
existing tools are in %s -- read it with `read_file` before creating a \
new tool, or any time you're unsure what capabilities you have."
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
