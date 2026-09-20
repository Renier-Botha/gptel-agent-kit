;;; tools-misc.el --- Misc hand-reviewed utility tools -*- lexical-binding: t; -*-

(require 'gptel)

(gptel-make-tool
 :name "diff_buffer"
 :function (lambda (buffer_name &optional path)
  (let ((buf (get-buffer buffer_name)))
    (if (not buf) (format "No such buffer: %s" buffer_name)
      (let*
          ((file
            (if (and path (not (string-empty-p path))) (expand-file-name path)
              (with-current-buffer buf (buffer-file-name))))
           (buf-content (with-current-buffer buf (buffer-string))))
        (cond
         ((not file)
          (format
           "Buffer %s is not visiting a file and no path was given -- nothing on disk to diff against."
           buffer_name))
         ((not (file-exists-p file))
          (format
           "%s does not exist on disk yet -- the whole buffer would be new content:\n\n%s"
           file
           (if (> (length buf-content) 4000)
               (concat (substring buf-content 0 4000) "\n[...truncated...]")
             buf-content)))
         (t
          (let ((buf-tmp (make-temp-file "gptel-diff-buf")) (result nil))
            (unwind-protect
                (progn
                  (with-temp-file buf-tmp (insert buf-content))
                  (with-temp-buffer
                    (call-process "diff" nil t nil "-u" file buf-tmp)
                    (goto-char (point-min))
                    (when (re-search-forward (regexp-quote buf-tmp) nil t)
                      (replace-match (format "%s (buffer)" buffer_name)))
                    (goto-char (point-min)) (setq result (buffer-string))))
              (delete-file buf-tmp))
            (if (string-empty-p result)
                (format "No differences between buffer %s and %s." buffer_name
                        file)
              (format "--- %s\n+++ %s (buffer)\n%s" file buffer_name
                      (mapconcat #'identity
                                 (seq-drop (split-string result "\n") 2) "\n"))))))))))

 :description "Show a unified diff between an already-open buffer's current (in-memory) contents and a file on disk -- by default the file the buffer is visiting, or an explicit path if given. Read-only: does not modify the buffer or the file. Use this after edit_buffer/write_buffer to sanity-check a change before calling save_buffer, or anytime you want to see what would change without applying anything."
 :args (list
 '(:name "buffer_name" :type string :description
   "Exact name of an already-open buffer")
 '(:name "path" :type string :optional t :description
   "File to diff against; defaults to the buffer's own visited file"))
 :confirm nil
 :category "misc")

(gptel-make-tool
 :name "revert_buffer"
 :function (lambda (buffer_name)
  (let ((buf (get-buffer buffer_name)))
    (cond ((not buf) (format "No such buffer: %s" buffer_name))
          ((not (with-current-buffer buf (buffer-file-name)))
           (format "Buffer %s is not visiting a file; nothing to revert to."
                   buffer_name))
          ((not (file-exists-p (with-current-buffer buf (buffer-file-name))))
           (format
            "Buffer %s's file %s no longer exists on disk; cannot revert."
            buffer_name (with-current-buffer buf (buffer-file-name))))
          (t
           (with-current-buffer buf
             (condition-case err
                 (progn
                   (revert-buffer t t t)
                   (format
                    "Reverted %s to the on-disk contents of %s. Any unsaved in-memory changes are gone."
                    buffer_name (buffer-file-name)))
               (error
                (format "Failed to revert %s: %s" buffer_name
                        (error-message-string err)))))))))
 :description "Discard an already-open file-visiting buffer's in-memory (possibly edited) contents and reload it fresh from disk. Use this to undo an edit_buffer/write_buffer change you haven't saved yet and don't want to keep. Only works on buffers visiting a file; refuses if the buffer has never been saved (no file to revert to) to avoid silent data loss."
 :args (list
 '(:name "buffer_name" :type string :description
   "Exact name of an already-open, file-visiting buffer to revert"))
 :confirm t
 :category "misc")

(gptel-make-tool
 :name "rename_file"
 :function (lambda (from to &optional overwrite)
  (let*
      ((src (expand-file-name from)) (dst (expand-file-name to))
       (overwrite (and overwrite (not (eq overwrite :json-false)))))
    (cond
     ((not (file-exists-p src)) (format "No such file or directory: %s" src))
     ((and (file-exists-p dst) (not overwrite))
      (format "%s already exists. Pass overwrite=true to replace it." dst))
     (t
      (condition-case err
          (progn
            (make-directory (file-name-directory dst) t)
            (rename-file src dst overwrite) (format "Renamed %s to %s" src dst))
        (error
         (format "Failed to rename %s to %s: %s" src dst
                 (error-message-string err))))))))
 :description "Rename or move a file or directory on disk (e.g. to fix a typo'd filename or reorganize a project). Creates parent directories of the destination as needed. Refuses to overwrite an existing destination unless overwrite=true. If a buffer is visiting the renamed file, that buffer is NOT automatically updated to point at the new path -- use read_file/write_file or reopen as needed afterward."
 :args (list
 '(:name "from" :type string :description
   "Existing file or directory path to rename/move")
 '(:name "to" :type string :description "New path/name")
 '(:name "overwrite" :type boolean :optional t :description
   "Required to be true if a file/directory already exists at the destination"))
 :confirm t
 :category "misc")

(gptel-make-tool
 :name "delete_file"
 :function (lambda (path)
  (let ((full (expand-file-name path)))
    (cond ((not (file-exists-p full)) (format "No such file: %s" full))
          ((file-directory-p full)
           (format
            "%s is a directory, not a file -- refusing to delete via this tool. Use run_shell_command if you really need to remove a directory."
            full))
          (t
           (condition-case err
               (progn (delete-file full) (format "Deleted %s" full))
             (error
              (format "Failed to delete %s: %s" full (error-message-string err))))))))
 :description "Delete a single file from disk. Refuses to delete directories (use run_shell_command for that if truly needed) or paths that don't exist. Irreversible -- there is no undo, so this is confirm-gated. If any buffer is visiting the file, that buffer is left open but will show a \"file deleted\" state; it is not killed."
 :args (list
 '(:name "path" :type string :description
   "Absolute or relative path to the file (not directory) to delete"))
 :confirm t
 :category "misc")

(gptel-make-tool
 :name "byte_compile_check"
 :function (lambda (&optional path buffer_name)
  (let*
      ((have-path (and path (not (string-empty-p path))))
       (have-buf (and buffer_name (not (string-empty-p buffer_name)))))
    (cond
     ((and have-path have-buf) "Pass only one of path or buffer_name, not both.")
     ((not (or have-path have-buf)) "Must pass either path or buffer_name.")
     (t
      (let*
          ((buf (and have-buf (get-buffer buffer_name))) (tmp nil) (target nil))
        (cond
         ((and have-buf (not buf)) (format "No such buffer: %s" buffer_name))
         (t
          (unwind-protect
              (progn
                (setq target
                      (if have-path (expand-file-name path)
                        (setq tmp
                              (make-temp-file "gptel-byte-compile-check" nil
                                              ".el"))
                        (with-temp-file tmp
                          (insert (with-current-buffer buf (buffer-string))))
                        tmp))
                (if (not (file-exists-p target))
                    (format "No such file: %s" target)
                  (let
                      ((log-buf
                        (get-buffer-create " *gptel-byte-compile-check*")))
                    (with-current-buffer log-buf
                      (let ((buffer-read-only nil)) (erase-buffer))
                      (let
                          ((byte-compile-log-buffer (buffer-name log-buf))
                           (byte-compile-warnings t))
                        (condition-case err (byte-compile-file target)
                          (error
                           (insert
                            (format "Byte-compile signaled an error: %s"
                                    (error-message-string err))))))
                      (let ((elc (concat target "c")))
                        (when (file-exists-p elc) (delete-file elc)))
                      (let ((result (string-trim (buffer-string))))
                        (if (string-empty-p result)
                            (format "%s byte-compiled cleanly, no warnings."
                                    (or path (format "buffer %s" buffer_name)))
                          (format "Byte-compile results for %s:\n%s"
                                  (or path (format "buffer %s" buffer_name))
                                  result)))))))
            (when tmp (ignore-errors (delete-file tmp)))))))))))
 :description "Byte-compile an Emacs Lisp file (by path) or an open buffer's current in-memory contents (by buffer_name) and return any byte-compiler warnings/errors as plain text, or a message saying it compiled cleanly. Read-only: never leaves a .elc file behind and never modifies the input. Use this to sanity-check Elisp you've written (e.g. via write_file/edit_buffer or define_tool) before considering it done -- exactly one of path or buffer_name must be given."
 :args (list
 '(:name "path" :type string :optional t :description
   "File path to byte-compile. Omit if passing buffer_name instead.")
 '(:name "buffer_name" :type string :optional t :description
   "Name of an already-open buffer to byte-compile (its current in-memory contents, written to a temp file first). Omit if passing path instead."))
 :confirm nil
 :category "misc")

(provide 'gptel-agent-tools-misc)
;;; tools-misc.el ends here
