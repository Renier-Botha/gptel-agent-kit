;;; tools-exec.el --- Execution tools for the gptel agent -*- lexical-binding: t; -*-

;; run_shell_command/eval_elisp are strictly more powerful than
;; anything in tools-edit.el, so they get their own on/off switch
;; (`gptel-agent-enable-exec-tools' / `-disable-exec-tools') separate
;; from `gptel-agent-disable-write-tools'.

(require 'gptel)
(declare-function gptel-agent--tools-set "tools-read")

(defvar gptel-agent-exec-tools nil
  "Tool structs registered by this file (run_shell_command,
eval_elisp). Enabled by default in `gptel-tools' -- see
`gptel-agent-disable-exec-tools' to opt out per-buffer.")

(defun gptel-agent--register-exec-tool (&rest args)
  "Register an execution tool via `gptel-make-tool', always
confirm-gated, and added to the default `gptel-tools' list."
  (let ((tool (apply #'gptel-make-tool (append args (list :confirm t)))))
    (gptel-agent--tools-set 'gptel-agent-exec-tools tool)
    tool))

;;;###autoload
(defun gptel-agent-enable-exec-tools ()
  "(Re-)enable run_shell_command/eval_elisp in the current buffer."
  (interactive)
  (setq-local gptel-tools (append gptel-agent-exec-tools
                                   (seq-difference gptel-tools gptel-agent-exec-tools)))
  (message "gptel-agent: exec tools enabled in %s (%d tools)"
           (buffer-name) (length gptel-agent-exec-tools)))

;;;###autoload
(defun gptel-agent-disable-exec-tools ()
  "Remove run_shell_command/eval_elisp from the current buffer's tool
list."
  (interactive)
  (setq-local gptel-tools (seq-difference gptel-tools gptel-agent-exec-tools))
  (message "gptel-agent: exec tools disabled in %s" (buffer-name)))

(defconst gptel-agent-exec-timeout 30
  "Seconds to wait for a shell command before killing it.")

(defconst gptel-agent-exec-max-output 20000
  "Max characters of shell output returned to the model before truncation.")

(defun gptel-agent--truncate-output (s)
  (if (> (length s) gptel-agent-exec-max-output)
      (concat (substring s 0 gptel-agent-exec-max-output)
              (format "\n...[truncated, %d total chars]" (length s)))
    s))

(gptel-agent--register-exec-tool
 :name "run_shell_command"
 :function
 (lambda (command &optional directory)
   (condition-case err
       (let* ((default-directory
               (if (and directory (not (string-empty-p directory)))
                   (file-name-as-directory (expand-file-name directory))
                 default-directory))
              (buf (generate-new-buffer " *gptel-agent-shell*"))
              (proc (start-process-shell-command "gptel-agent-shell" buf command))
              (deadline (+ (float-time) gptel-agent-exec-timeout)))
         (unwind-protect
             (progn
               (while (and (process-live-p proc) (< (float-time) deadline))
                 (accept-process-output proc 0.2))
               (if (process-live-p proc)
                   (progn (kill-process proc)
                          (format "Command timed out after %ds in %s:\n%s\n[killed]"
                                  gptel-agent-exec-timeout default-directory
                                  (gptel-agent--truncate-output
                                   (with-current-buffer buf (buffer-string)))))
                 (let ((status (process-exit-status proc))
                       (output (with-current-buffer buf (buffer-string))))
                   (format "$ %s\n(cwd: %s, exit: %d)\n%s"
                           command default-directory status
                           (gptel-agent--truncate-output
                            (if (string-empty-p output) "[no output]" output))))))
           (kill-buffer buf)))
     (error (format "Failed to run command: %s" (error-message-string err)))))
 :description "Run a shell command via the user's shell and return its
combined stdout+stderr, exit code, and the working directory it ran
in. Runs synchronously with a timeout (currently 30s); long-running
commands will be killed and reported as timed out. Output is
truncated past ~20000 characters. Use for things like running tests,
git, build tools, find/rg, etc. This has full privileges of the
user's shell -- nothing is sandboxed, so avoid destructive commands
unless explicitly asked, and prefer read-only/idempotent commands
when just exploring."
 :args (list '(:name "command" :type string
               :description "Shell command to run, e.g. \"git status\" or \"npm test\"")
             '(:name "directory" :type string :optional t
               :description "Directory to run the command in; defaults to Emacs's current default-directory if omitted"))
 :category "emacs-exec")

(gptel-agent--register-exec-tool
 :name "eval_elisp"
 :function
 (lambda (expression)
   (condition-case err
       (let ((result (eval (car (read-from-string expression)) t)))
         (format "=> %s" (prin1-to-string result)))
     (error (format "Elisp error: %s" (error-message-string err)))))
 :description "Evaluate a single Emacs Lisp expression (a string of
Lisp source, e.g. \"(+ 1 2)\" or \"(buffer-name)\") in the running
Emacs session and return the printed result, or an error message if
it signals. This has full Elisp privileges -- it can read/write any
buffer or file, run arbitrary computation, or change Emacs's own
state/settings -- there is no sandboxing. Prefer the narrower
read/write tools (read_file, edit_buffer, etc.) when they suffice;
use this for one-off introspection or operations that don't fit an
existing tool, and use `run_shell_command' for shell-level tasks
instead. Only a single top-level form is evaluated; wrap multiple
forms in a (progn ...)."
 :args (list '(:name "expression" :type string
               :description "Emacs Lisp source text of one expression to evaluate, e.g. \"(progn (message \\\"hi\\\") (+ 1 2))\""))
 :category "emacs-exec")

(provide 'gptel-agent-tools-exec)
;;; tools-exec.el ends here
