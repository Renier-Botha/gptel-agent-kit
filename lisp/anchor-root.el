;;; anchor-root.el --- Stable per-buffer root for path resolution -*- lexical-binding: t; -*-

;; Problem this fixes (see gptel-agent-notes.org, 2026-09-21):
;; tool path resolution (write_file, edit_buffer via buffer name,
;; @ref resolution) all key off whatever `default-directory'/
;; `project-current' happens to be *at call time*. When several
;; project worktrees are open, ambient `default-directory' can
;; silently differ between two tool calls in the very same exchange
;; (e.g. because point moved, or a previous tool call changed
;; buffers), with no stable "which project root are we talking
;; about" anchor per conversation.
;;
;; Fix: the first time a gptel chat buffer needs a root (via any of
;; the read/write/@ref tools below), resolve it once from that
;; buffer's own `default-directory'/`project-current' and cache it
;; buffer-locally. From then on, everything in this conversation
;; consults the cached anchor instead of re-deriving it from
;; whatever happens to be ambient. This is intentionally *buffer*-
;; local (one gptel chat buffer == one conversation), not global.

(require 'gptel)
(require 'project)

(defvar-local gptel-agent-anchor-root nil
  "Cached project/working root for this gptel conversation buffer, or
nil if not yet resolved. Set lazily by `gptel-agent-anchor-root'; use
`gptel-agent-reset-anchor-root' to force it to be re-derived (e.g.
after `cd`-ing a shell buffer, or if you actually did mean to switch
projects mid-conversation).")

(defun gptel-agent--derive-root (&optional buffer)
  "Derive a root directory from BUFFER's (or the current buffer's)
`default-directory'/`project-current', without touching the cache."
  (with-current-buffer (or buffer (current-buffer))
    (file-name-as-directory
     (expand-file-name
      (if-let ((proj (project-current))) (project-root proj) default-directory)))))

(defun gptel-agent-anchor-root (&optional buffer)
  "Return the stable anchor root for BUFFER (or the current buffer),
resolving and caching it on first use. Subsequent calls from the same
buffer return the same directory even if ambient `default-directory'
or `project-current' would now disagree -- that drift is exactly the
bug this exists to paper over. Tool functions are generally invoked
with the gptel conversation buffer current, so calling this with no
argument from inside a tool's `:function' body is the normal use."
  (with-current-buffer (or buffer (current-buffer))
    (or gptel-agent-anchor-root
        (setq gptel-agent-anchor-root (gptel-agent--derive-root)))))

;;;###autoload
(defun gptel-agent-reset-anchor-root ()
  "Forget this buffer's cached anchor root, so it's re-derived from
current `default-directory'/`project-current' on next use. Use this if
you deliberately want to point the rest of the conversation at a
different project/worktree."
  (interactive)
  (setq-local gptel-agent-anchor-root nil)
  (message "gptel-agent: anchor root cleared in %s; will be re-derived from %s on next use."
           (buffer-name) default-directory))

;;;###autoload
(defun gptel-agent-show-anchor-root ()
  "Display this buffer's current anchor root (deriving it now if not
already cached), so you can sanity-check what tools/@refs are
resolving relative paths against."
  (interactive)
  (message "gptel-agent: anchor root for %s is %s"
           (buffer-name) (gptel-agent-anchor-root)))

(defun gptel-agent-expand-under-anchor (path)
  "Expand PATH (absolute or relative) against this buffer's anchor
root rather than ambient `default-directory'. Absolute paths are
returned as-is (still passed through `expand-file-name' for
normalization); relative paths are resolved against
`gptel-agent-anchor-root'."
  (expand-file-name path (gptel-agent-anchor-root)))

(provide 'gptel-agent-anchor-root)
;;; anchor-root.el ends here
