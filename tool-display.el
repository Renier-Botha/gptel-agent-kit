;;; tool-display.el --- Nicer confirmation display for our write tools -*- lexical-binding: t; -*-

;; gptel's default confirmation prompt prin1-escapes multi-line
;; arguments, which is unreadable. This advises gptel's internal
;; formatter (`gptel--format-tool-call', unstable/internal -- may need
;; updating if gptel changes it) to render our own write tools as a
;; diff instead, falling back to the original formatter for everything
;; else. Purely cosmetic; never changes what actually runs.

(require 'gptel)

(defun gptel-agent--pretty-diff-string (old new)
  "Return a unified-diff string (propertized) between strings OLD and NEW.
Falls back to a plain message if the two are identical, or to raw
`diff' output if something goes wrong."
  (if (string= old new)
      (propertize "(no changes -- new content is identical to what's already there)"
                  'font-lock-face 'font-lock-comment-face)
    (let ((old-tmp (make-temp-file "gptel-diff-old"))
          (new-tmp (make-temp-file "gptel-diff-new"))
          (result nil))
      (unwind-protect
          (progn
            (with-temp-file old-tmp (insert old))
            (with-temp-file new-tmp (insert new))
            (with-temp-buffer
              (call-process "diff" nil t nil "-u" old-tmp new-tmp)
              (goto-char (point-min))
              (when (re-search-forward (regexp-quote old-tmp) nil t)
                (replace-match "old"))
              (goto-char (point-min))
              (when (re-search-forward (regexp-quote new-tmp) nil t)
                (replace-match "new"))
              (goto-char (point-min))
              (setq result (buffer-string))))
        (delete-file old-tmp)
        (delete-file new-tmp))
      ;; Drop the two --- /+++ header lines (already redundant with the
      ;; tool-name/target line printed by the caller) and colorize hunks.
      (mapconcat
       (lambda (line)
         (cond
          ((string-prefix-p "+" line) (propertize line 'font-lock-face 'diff-added))
          ((string-prefix-p "-" line) (propertize line 'font-lock-face 'diff-removed))
          ((string-prefix-p "@@" line) (propertize line 'font-lock-face 'diff-hunk-header))
          (t line)))
       (seq-drop (split-string result "\n") 2)
       "\n"))))

(defun gptel-agent--existing-content-for (tool-name target)
  "Return existing content TARGET currently has, for TOOL-NAME's write, or nil.
For write_file, TARGET is a path; for write_buffer, a buffer name.
Returns nil if there's nothing to diff against (new file/buffer)."
  (pcase tool-name
    ("write_file"
     (let ((file (expand-file-name target)))
       (when (and (file-exists-p file) (not (file-directory-p file)))
         (with-temp-buffer (insert-file-contents file) (buffer-string)))))
    ("write_buffer"
     (let ((buf (get-buffer target)))
       (when (and buf (> (buffer-size buf) 0))
         (with-current-buffer buf (buffer-string)))))))

(defun gptel-agent--format-tool-call-pretty (orig-fn name arg-values)
  "Pretty-print confirmation display for select write tools; defer to
ORIG-FN (the original `gptel--format-tool-call') for everything else.
NAME is the tool name string, ARG-VALUES its positional arguments."
  (pcase name
    ("edit_buffer"
     (pcase-let ((`(,buffer_name ,old_string ,new_string) arg-values))
       (format "%s %s\n%s\n%s\n%s\n%s\n"
               (propertize name 'font-lock-face 'font-lock-keyword-face)
               (propertize (format "%s" buffer_name) 'font-lock-face 'font-lock-constant-face)
               (propertize "--- old_string" 'font-lock-face 'diff-header)
               (propertize (format "%s" old_string) 'font-lock-face 'diff-removed)
               (propertize "+++ new_string" 'font-lock-face 'diff-header)
               (propertize (format "%s" new_string) 'font-lock-face 'diff-added))))
    ((or "write_file" "write_buffer")
     (pcase-let ((`(,target ,content . ,_) arg-values))
       (let ((existing (gptel-agent--existing-content-for name target)))
         (if existing
             ;; Overwriting something that already exists on disk/in a
             ;; buffer: show a real unified diff instead of dumping the
             ;; whole new content.
             (format "%s %s\n%s"
                     (propertize name 'font-lock-face 'font-lock-keyword-face)
                     (propertize (format "%s" target) 'font-lock-face 'font-lock-constant-face)
                     (gptel-agent--pretty-diff-string existing content))
           (format "%s %s\n%s\n%s\n"
                   (propertize name 'font-lock-face 'font-lock-keyword-face)
                   (propertize (format "%s" target) 'font-lock-face 'font-lock-constant-face)
                   (propertize "--- new content" 'font-lock-face 'diff-header)
                   (propertize (format "%s" content) 'font-lock-face 'diff-added))))))
    (_ (funcall orig-fn name arg-values))))

(advice-add 'gptel--format-tool-call :around #'gptel-agent--format-tool-call-pretty)

(provide 'gptel-agent-tool-display)
;;; tool-display.el ends here
