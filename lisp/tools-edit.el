;;; tools-edit.el --- Write tools for the gptel agent -*- lexical-binding: t; -*-

;; Write tools: :confirm t, so gptel prompts before every call.
;; Enabled by default in `gptel-tools'; toggle with
;; `gptel-agent-disable-write-tools' / `-enable-write-tools'.

(require 'gptel)

(declare-function gptel-agent--bool "tools-read")
(declare-function gptel-agent--tools-set "tools-read")
(declare-function gptel-agent-expand-under-anchor "anchor-root")
(declare-function gptel-agent-anchor-root "anchor-root")

(defvar gptel-agent-write-tools nil
  "Tool structs registered by this file. Enabled by default in
`gptel-tools' -- see `gptel-agent-disable-write-tools' to opt out
per-buffer, and `gptel-agent-enable-write-tools' to opt back in.")

(defun gptel-agent--register-write-tool (&rest args)
  "Register a write tool via `gptel-make-tool', confirm-gated, and
added to the default `gptel-tools' list. Each call still requires
explicit confirmation, which is why it's safe to enable by default."
  (let ((tool (apply #'gptel-make-tool (append args (list :confirm t)))))
    (gptel-agent--tools-set 'gptel-agent-write-tools tool)
    tool))

;;;###autoload
(defun gptel-agent-enable-write-tools ()
  "(Re-)enable gptel's write tools (edit_buffer, write_file,
save_buffer) in the current buffer. They're already on by default;
this is for turning them back on after a `gptel-agent-disable-write-tools'
call. Each call still requires your explicit confirmation via gptel's
tool-confirmation prompt regardless."
  (interactive)
  (setq-local gptel-tools (append gptel-agent-write-tools
                                   (seq-difference gptel-tools gptel-agent-write-tools)))
  (message "gptel-agent: write tools enabled in %s (%d tools)"
           (buffer-name) (length gptel-agent-write-tools)))

;;;###autoload
(defun gptel-agent-disable-write-tools ()
  "Remove gptel's write tools from the current buffer's tool list, if
you want a strictly read-only conversation. Use
`gptel-agent-enable-write-tools' to turn them back on."
  (interactive)
  (setq-local gptel-tools (seq-difference gptel-tools gptel-agent-write-tools))
  (message "gptel-agent: write tools disabled in %s" (buffer-name)))

(defun gptel-agent--buffer-replace-unique (buffer old-string new-string)
  "Replace the unique occurrence of OLD-STRING with NEW-STRING in
BUFFER. Returns a plain-English result string describing what
happened; never signals an error (so the model gets a clear message
back instead of a stack trace)."
  (with-current-buffer buffer
    (let ((count 0) (first-match nil))
      (save-excursion
        (goto-char (point-min))
        (while (search-forward old-string nil t)
          (setq count (1+ count))
          (unless first-match (setq first-match (match-beginning 0)))))
      (cond
       ((zerop count)
        (format "old_string not found in buffer %s -- no changes made."
                (buffer-name)))
       ((> count 1)
        (format "old_string matches %d locations in buffer %s, not unique -- include more surrounding context so it matches exactly once. No changes made."
                count (buffer-name)))
       (t
        (save-excursion
          (goto-char first-match)
          (search-forward old-string)
          (replace-match new-string t t))
        (format "Replaced the 1 occurrence in buffer %s%s. Buffer is now modified but unsaved -- call save_buffer if you want this written to disk."
                (buffer-name)
                (if buffer-file-name (format " (visiting %s)" buffer-file-name) " (not visiting a file)")))))))

(gptel-agent--register-write-tool
 :name "edit_buffer"
 :function
 (lambda (buffer_name old_string new_string)
   (if-let ((buf (get-buffer buffer_name)))
       (gptel-agent--buffer-replace-unique buf old_string new_string)
     (format "No such buffer: %s" buffer_name)))
 :description "Replace an exact, unique substring in an already-open
buffer. old_string must match one location in the buffer exactly
(including whitespace/indentation) -- if it matches zero or multiple
locations, no change is made and you'll get an error telling you why.
Include enough surrounding context in old_string to make it unique
rather than guessing. This only edits the in-memory buffer; call
save_buffer afterwards to persist to disk. If the buffer doesn't exist
yet (e.g. you want to draft something in a new scratch buffer), use
write_buffer to create it first."
 :args (list '(:name "buffer_name" :type string
               :description "Exact name of an already-open buffer")
             '(:name "old_string" :type string
               :description "Exact text to replace; must be unique in the buffer")
             '(:name "new_string" :type string
               :description "Replacement text"))
 :category "emacs-write")

(gptel-agent--register-write-tool
 :name "write_buffer"
 :function
 (lambda (buffer_name content &optional overwrite)
   (let* ((overwrite (gptel-agent--bool overwrite))
          (existing (get-buffer buffer_name))
          (non-empty (and existing (with-current-buffer existing
                                      (> (buffer-size) 0)))))
     (if (and non-empty (not overwrite))
         (format "Buffer %s already exists and is non-empty. Pass overwrite=true to replace its entire contents, or use edit_buffer for a targeted change."
                 buffer_name)
       (with-current-buffer (get-buffer-create buffer_name)
         (erase-buffer)
         (insert content)
         (format "%s buffer %s with %d characters in %s. It is not visiting a file (nothing to save_buffer) unless you write it out with write_file."
                 (if existing "Replaced contents of" "Created")
                 buffer_name (length content) default-directory)))))
 :description "Create a brand-new, file-less Emacs buffer (e.g. a
scratch/notes/draft buffer) with the given content, or replace an
existing non-file buffer's entire contents with overwrite=true. Use
this instead of write_file when there's no reason for the content to
live on disk as a file. Use edit_buffer instead if you just want to
make a small change to a buffer that already has substantial content."
 :args (list '(:name "buffer_name" :type string
               :description "Name for the buffer, e.g. \"*notes*\" or \"draft.md\"")
             '(:name "content" :type string
               :description "Full content to put in the buffer")
             '(:name "overwrite" :type boolean :optional t
               :description "Required to be true if the buffer already exists and has content"))
 :category "emacs-write")

(gptel-agent--register-write-tool
 :name "write_file"
 :function
 (lambda (path content &optional overwrite)
   (let ((full (gptel-agent-expand-under-anchor path))
         (overwrite (gptel-agent--bool overwrite)))
     (cond
      ((and (file-exists-p full) (not overwrite))
       (format "%s already exists. Pass overwrite=true to replace its entire contents, or prefer edit_buffer for a targeted change to something already open."
               full))
      (t
       (make-directory (file-name-directory full) t)
       (with-temp-file full (insert content))
       (format "Wrote %d bytes to %s (resolved against this conversation's anchor root %s)"
               (length content) full (gptel-agent-anchor-root))))))
 :description "Create a new file with the given content, or (with
overwrite=true) replace an existing file's entire contents. Creates
parent directories as needed. Prefer edit_buffer for small, targeted
changes to a file that's already open -- this tool replaces the whole
file body."
 :args (list '(:name "path" :type string
               :description "Absolute or relative path to write to")
             '(:name "content" :type string
               :description "Full content to write to the file")
             '(:name "overwrite" :type boolean :optional t
               :description "Required to be true if the file already exists"))
 :category "emacs-write")

(gptel-agent--register-write-tool
 :name "save_buffer"
 :function
 (lambda (buffer_name)
   (if-let ((buf (get-buffer buffer_name)))
       (with-current-buffer buf
         (if (buffer-file-name)
             (progn (save-buffer)
                    (format "Saved buffer %s to file %s (project root: %s)"
                            buffer_name (buffer-file-name)
                            (or (and (project-current) (project-root (project-current)))
                                "none detected")))
           (format "Buffer %s is not visiting a file; nothing to save."
                   buffer_name)))
     (format "No such buffer: %s" buffer_name)))
 :description "Persist an already-modified buffer's contents to the
file it's visiting on disk. Call this after edit_buffer if you want
the change written to disk, not just held in the buffer."
 :args (list '(:name "buffer_name" :type string
               :description "Exact name of an already-open, file-visiting buffer"))
 :category "emacs-write")

(provide 'gptel-agent-tools-edit)
;;; tools-edit.el ends here
