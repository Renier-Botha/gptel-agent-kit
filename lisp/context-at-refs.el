;;; context-at-refs.el --- @path/@buffer context expansion -*- lexical-binding: t; -*-

;; Adds Aider/Cursor-style "@thing" ergonomics to gptel: typing
;; "@some-file.el" or "@some-buffer-name" in a prompt inlines that
;; file's/buffer's contents before the request is sent.
;;
;; Implemented as a `gptel-prompt-transform-functions' hook, which
;; runs in a temporary copy of the outgoing prompt -- so this only
;; affects the text sent for *this* request, no persistent state.

(require 'gptel)
(require 'project)
(require 'cl-lib)
;; `gptel-agent--truncate' is defined in tools-read.el, loaded before
;; this file by core/init.el. `gptel-agent-anchor-root'/
;; `gptel-agent-expand-under-anchor' are defined in anchor-root.el,
;; also loaded before this file.
(declare-function gptel-agent--truncate "tools-read")
(declare-function gptel-agent-anchor-root "anchor-root")
(declare-function gptel-agent-expand-under-anchor "anchor-root")

(defvar gptel-agent-at-ref-regexp
  "\\(^\\|[[:space:]]\\)@\\([[:alnum:]_./*-]+\\)"
  "Regexp matching @refs in a prompt.
Group 1 is the character before `@' (or empty at line start).
Group 2 is the ref itself (buffer name or file path), without the `@'.
Includes `*' so internal buffer names like *scratch* or *Messages*
can be referenced. Known limitation: trailing sentence punctuation
(e.g. a ref immediately followed by a period at end of sentence)
becomes part of the ref and will simply fail to resolve -- harmless,
but means such refs need a space before the period to expand.")

(defvar gptel-agent-at-ref-resolvers nil
  "List of functions tried in order to resolve an @ref.
Each function takes REF (the text after `@', a string) and returns
either resolved content as a string, or nil to defer to the next
resolver. Populated with buffer/file resolution by this file (first,
so it always wins); other modules (e.g. skills.el) can extend it with
=(add-to-list \\='gptel-agent-at-ref-resolvers #\\='my-resolver t)= -- the
trailing t appends, so more specific/local things stay checked first.")

(defun gptel-agent--at-ref-root (&optional fsm)
  "Return the anchor root to resolve @refs against. Prompt expansion
runs with a temporary prompt-construction buffer current (not the
actual gptel conversation buffer), so when FSM (the state machine
gptel passes to prompt-transform-functions) is available, look up the
original conversation buffer via its `:buffer' info and anchor
against that instead -- otherwise the anchor cache would be set on a
throwaway buffer and re-derived from scratch on every single request."
  (let ((orig (and fsm (fboundp 'gptel-fsm-info)
                    (plist-get (gptel-fsm-info fsm) :buffer))))
    (if (buffer-live-p orig)
        (gptel-agent-anchor-root orig)
      (gptel-agent-anchor-root))))

(defun gptel-agent--resolve-buffer-or-file-ref (ref &optional fsm)
  "Resolve REF to an open buffer, a file, or a directory, returning
its contents (or, for a directory, a recursive file listing) as a
string, or nil if REF doesn't resolve to any of those. Tries an open
buffer named REF first, then a path resolved against this
conversation's anchored root (see anchor-root.el)."
  (cond
   ((get-buffer ref)
    (with-current-buffer (get-buffer ref) (buffer-string)))
   (t
    (let ((path (expand-file-name ref (gptel-agent--at-ref-root fsm))))
      (when (file-exists-p path)
        (if (file-directory-p path)
            (mapconcat (lambda (f) (file-relative-name f path))
                       (directory-files-recursively path "." nil)
                       "\n")
          (with-temp-buffer
            (insert-file-contents path)
            (buffer-string))))))))

(add-to-list 'gptel-agent-at-ref-resolvers #'gptel-agent--resolve-buffer-or-file-ref t)

(defun gptel-agent--resolve-at-ref (ref &optional fsm)
  "Resolve REF (text after `@') by trying each function in
`gptel-agent-at-ref-resolvers' in turn, returning the first non-nil
result, or nil if none resolve it. FSM (if supplied) is passed to any
resolver whose arity accepts a second argument, so resolvers that care
about the anchored conversation root (see `gptel-agent--at-ref-root')
can use it."
  (cl-some (lambda (fn)
             (if (>= (cdr (func-arity fn)) 2)
                 (funcall fn ref fsm)
               (funcall fn ref)))
           gptel-agent-at-ref-resolvers))

(defun gptel-agent-expand-at-refs (&optional fsm)
  "Expand @refs in the current prompt-construction buffer in place.
Intended for `gptel-prompt-transform-functions'; see file commentary."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward gptel-agent-at-ref-regexp nil t)
      (let* ((ref (match-string 2))
             (start (match-end 1))   ; position of the literal "@"
             (end (match-end 0))     ; end of the ref text
             (content (gptel-agent--resolve-at-ref ref fsm)))
        (delete-region start end)
        (goto-char start)
        (if content
            (insert (format "\n```%s\n%s\n```\n" ref (gptel-agent--truncate content)))
          (insert (format "@%s [gptel-agent: could not resolve \"%s\" as an open buffer or a file/directory under this conversation's anchored root %s -- this does NOT necessarily mean it doesn't exist; use list_directory/grep_project/list_project_files to locate it rather than shelling out to find/cat]"
                           ref ref
                           (gptel-agent--at-ref-root fsm))))))))

(add-hook 'gptel-prompt-transform-functions #'gptel-agent-expand-at-refs)

;; --- gptel-agent-insert-file-ref: C-x C-f-style @ref picker ------------

;;;###autoload
(defun gptel-agent-insert-file-ref ()
  "Prompt for a file or directory with the same completion UI as
`find-file' (`read-file-name', so it autocompletes paths as you type,
supports all the usual minibuffer/ido/vertico/etc. completion you
already use for C-x C-f), then insert it at point as \"@path \" --
the same @ref syntax `gptel-agent-expand-at-refs' expands before the
prompt is sent. Unlike `find-file' this never visits/opens the file;
it only inserts a reference to it. Referencing a directory expands to
a recursive file listing (via `gptel-agent--resolve-buffer-or-file-ref'),
not the directory's file contents. Bound to C-c C-f in `gptel-mode-map'."
  (interactive)
  (let* ((path (expand-file-name (read-file-name "Attach file: " default-directory nil t)))
         (root (gptel-agent-anchor-root))
         (rel (file-relative-name path root)))
    (insert (format "@%s " rel))))

;; Bind directly into gptel-mode-map, mirroring skills.el's C-c C-a
;; binding and gptel's own C-c C-c convention.
(define-key gptel-mode-map (kbd "C-c C-f") #'gptel-agent-insert-file-ref)

(provide 'gptel-agent-context-at-refs)
;;; context-at-refs.el ends here
