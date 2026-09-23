;;; init.el --- Entry point for the gptel agent extensions -*- lexical-binding: t; -*-

;; Loaded from doom/config.el via a single line:
;;   (let ((init (expand-file-name "~/.config/gptel/core/init.el")))
;;     (when (file-exists-p init) (load init)))

(require 'gptel)
(require 'cl-lib)

(defconst gptel-agent-root
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the gptel agent core (this file's directory).")

(defconst gptel-agent-lisp-dir
  (expand-file-name "lisp/" gptel-agent-root)
  "Directory containing this package's hand-written Elisp modules.")

(defconst gptel-agent-tools-dir
  (expand-file-name "../tools/" gptel-agent-root)
  "Directory where the model's self-authored tools are written and loaded from.
Never hand-edit files in this directory -- it exists so a `git diff'
here shows exactly what the assistant has given itself over time.")

(unless (file-directory-p gptel-agent-tools-dir)
  (make-directory gptel-agent-tools-dir t))

;; Load our own hand-written modules, in dependency order.
(dolist (module '("anchor-root" "tools-read" "tools-edit" "tools-exec" "tools-misc" "tool-display" "context-at-refs" "skills" "meta-tool" "approve-all" "system-prompt"))
  (let ((file (expand-file-name (concat module ".el") gptel-agent-lisp-dir)))
    (if (file-exists-p file)
        (load file)
      (message "gptel-agent: skipping missing module %s (not built yet)" module))))

;; Load any tools the model has previously written for itself, so they
;; persist across Emacs restarts.
(when (file-directory-p gptel-agent-tools-dir)
  (dolist (file (directory-files gptel-agent-tools-dir t "\\.el\\'"))
    (condition-case err
        (load file)
      (error (message "gptel-agent: failed to load generated tool %s: %s" file err)))))

;; Safety net: `define_tool' (meta-tool.el) validates :args before
;; writing a new tool file, but that check postdates some tools that
;; may already be on disk. A tool with a malformed :args plist doesn't
;; fail to load -- `gptel-make-tool' doesn't validate -- it just sits
;; in `gptel-tools' until the *next* gptel-send, at which point every
;; backend's tool-schema builder calls `plist-get' on each arg spec
;; unconditionally and signals `wrong-type-argument plistp', breaking
;; every subsequent request in every gptel buffer until Emacs is
;; restarted or the offending tool is removed by hand. Strip any such
;; tool here instead, once, at startup, so a bad file on disk can only
;; ever break itself, not the whole session.
(when (fboundp 'gptel-agent--valid-arg-spec-p)
  (dolist (tool (copy-sequence gptel-tools))
    (unless (cl-every #'gptel-agent--valid-arg-spec-p (gptel-tool-args tool))
      (message "gptel-agent: disabling tool '%s' -- malformed :args would break every gptel request; inspect/fix/delete its file under %s"
                (gptel-tool-name tool) gptel-agent-tools-dir)
      (setq gptel-tools (delq tool gptel-tools)))))

(provide 'gptel-agent-init)
;;; init.el ends here
