;;; tools-read.el --- Read-only tools for the gptel agent -*- lexical-binding: t; -*-

;; None of these mutate anything, so they're :confirm nil and enabled
;; by default.

(require 'gptel)
(require 'project)
(declare-function gptel-agent-anchor-root "anchor-root")
(declare-function gptel-agent-expand-under-anchor "anchor-root")

(defvar gptel-agent-read-tools nil
  "Tool structs registered by this file, kept for inspection/debugging.")

(defvar gptel-agent-max-read-bytes (* 200 1024)
  "Cap on how much text a single read tool will return, to avoid
blowing the context window on huge files/buffers.")

(defun gptel-agent--truncate (string)
  "Truncate STRING to `gptel-agent-max-read-bytes', noting if it was cut."
  (if (> (length string) gptel-agent-max-read-bytes)
      (concat (substring string 0 gptel-agent-max-read-bytes)
              (format "\n\n[...truncated, %d bytes total...]" (length string)))
    string))

(defun gptel-agent--bool (value)
  "Coerce VALUE (a raw tool-call argument) to a proper Elisp boolean.
JSON `false' arrives from gptel as the symbol `:json-false', which is
non-nil in Elisp and would otherwise be treated as truthy by a plain
`(if value ...)' check -- every optional boolean tool argument in this
tree must be passed through this function before being tested."
  (and value (not (eq value :json-false))))

(defun gptel-agent--tools-set (list-var tool)
  "Add TOOL to the list bound to symbol LIST-VAR and to `gptel-tools',
removing any existing entries with the same name first. Without this,
re-evaluating one of these tool-definition files (e.g. while developing
it) creates a fresh tool struct that isn't `equal' to the previous one
\(different closure), so plain `add-to-list'/`push' would silently
accumulate two tools with the same name -- which the Copilot API
rejects with a 400 \='Tool names must be unique\=' error."
  (let* ((name (gptel-tool-name tool))
         (other-p (lambda (tl) (not (equal (gptel-tool-name tl) name)))))
    (set list-var (cons tool (seq-filter other-p (symbol-value list-var))))
    (setq gptel-tools (cons tool (seq-filter other-p gptel-tools)))))

(defun gptel-agent--register-read-tool (&rest args)
  "Register a read-only tool via `gptel-make-tool' with sane defaults,
and enable it by default in `gptel-tools'."
  (let ((tool (apply #'gptel-make-tool (append args (list :confirm nil)))))
    (gptel-agent--tools-set 'gptel-agent-read-tools tool)
    tool))

(gptel-agent--register-read-tool
 :name "read_buffer"
 :function
 (lambda (buffer_name)
   (if-let ((buf (get-buffer buffer_name)))
       (gptel-agent--truncate (with-current-buffer buf (buffer-string)))
     (format "No such buffer: %s" buffer_name)))
 :description "Return the full text of an already-open Emacs buffer.
Use list_open_buffers first if you don't know the exact buffer name."
 :args (list '(:name "buffer_name" :type string
               :description "Exact buffer name, e.g. \"init.el\" or \"*scratch*\""))
 :category "emacs-read")

(gptel-agent--register-read-tool
 :name "read_file"
 :function
 (lambda (path)
   (let ((full (gptel-agent-expand-under-anchor path)))
     (cond
      ((not (file-exists-p full)) (format "No such file: %s" full))
      ((file-directory-p full) (format "%s is a directory, not a file" full))
      (t (gptel-agent--truncate
          (with-temp-buffer
            (insert-file-contents full)
            (buffer-string)))))))
 :description "Read a file from disk by path (absolute, or relative to
this conversation's anchored root -- see gptel-agent-anchor-root).
Prefer read_buffer for files that are already open in a buffer."
 :args (list '(:name "path" :type string
               :description "Absolute or relative filesystem path"))
 :category "emacs-read")

(gptel-agent--register-read-tool
 :name "list_open_buffers"
 :function
 (lambda ()
   (let ((names (seq-filter
                 (lambda (name) (not (string-prefix-p " " name)))
                 (mapcar #'buffer-name (buffer-list)))))
     (mapconcat #'identity names "\n")))
 :description "List the names of all visible (non-internal) open Emacs
buffers, so the model knows what's currently available to read_buffer."
 :args nil
 :category "emacs-read")

(gptel-agent--register-read-tool
 :name "list_directory"
 :function
 (lambda (path &optional recursive)
   (let ((full (gptel-agent-expand-under-anchor (or path ".")))
         (recursive (gptel-agent--bool recursive)))
     (cond
      ((not (file-exists-p full)) (format "No such path: %s" full))
      ((not (file-directory-p full))
       (format "%s is a file, not a directory (use read_file)" full))
      (recursive
       (gptel-agent--truncate
        (mapconcat (lambda (f) (file-relative-name f full))
                   (directory-files-recursively full "." nil)
                   "\n")))
      (t (gptel-agent--truncate
          (mapconcat
           (lambda (name)
             (concat (if (file-directory-p (expand-file-name name full)) "d " "- ") name))
           (sort (directory-files full nil "^[^.]") #'string<)
           "\n"))))))
 :description "List the contents of a directory. Works for any path on
disk, independent of project detection -- use this (not
list_project_files) when the path isn't inside a recognized project,
or when you just need to browse a folder. Non-recursive by default;
pass recursive=true to list all files under the path."
 :args (list '(:name "path" :type string
               :description "Absolute or relative directory path")
             '(:name "recursive" :type boolean :optional t
               :description "If true, list all files recursively instead of just the immediate directory"))
 :category "emacs-read")

(gptel-agent--register-read-tool
 :name "list_project_files"
 :function
 (lambda ()
   (if-let ((proj (project-current nil (gptel-agent-anchor-root))))
       (mapconcat #'identity (project-files proj) "\n")
     (format "Not inside a known project (project-current returned nil). Use list_directory %S instead." (gptel-agent-anchor-root))))
 :description "List all files tracked by the current project (per
project.el, usually the nearest VCS root). Use to find a file by name
before calling read_file. Falls back to suggesting list_directory if
there's no recognized project (e.g. a plain directory with no VCS)."
 :args nil
 :category "emacs-read")

(gptel-agent--register-read-tool
 :name "grep_project"
 :function
 (lambda (pattern &optional path)
   (let* ((root (cond
                 (path (gptel-agent-expand-under-anchor path))
                 (t (gptel-agent-anchor-root)))))
     (cond
      ((not (file-directory-p root)) (format "No such directory: %s" root))
      ((not (executable-find "rg"))
       "ripgrep (rg) not found on PATH; grep_project requires it.")
      (t (gptel-agent--truncate
          (with-temp-buffer
            (call-process "rg" nil t nil
                           "--line-number" "--no-heading" "--color=never"
                           pattern root)
            (buffer-string)))))))
 :description "Search a directory tree for a regexp pattern using
ripgrep, returning matches as \"file:line:text\" lines. Defaults to
this conversation's anchored root (see gptel-agent-anchor-root) --
pass an explicit path to search anywhere else."
 :args (list '(:name "pattern" :type string
               :description "Regexp to search for (ripgrep/rg syntax)")
             '(:name "path" :type string :optional t
               :description "Directory to search in. Defaults to the current project root, or the current directory if there's no project."))
 :category "emacs-read")

(provide 'gptel-agent-tools-read)
;;; tools-read.el ends here
