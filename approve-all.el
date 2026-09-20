;;; approve-all.el --- Buffer-local bulk-approval toggle -*- lexical-binding: t; -*-

;; Overrides gptel's `gptel-confirm-tool-calls' buffer-locally to skip
;; confirmation for ALL tools (not just ours) -- for bursts of bulk
;; work like scaffolding a project. Does not persist across restarts.

(require 'gptel)

(defvar-local gptel-agent--saved-confirm-tool-calls nil
  "This buffer's `gptel-confirm-tool-calls' value from before
`gptel-agent-approve-all-enable' was called, restored by
`gptel-agent-approve-all-disable'.")

;;;###autoload
(defun gptel-agent-approve-all-enable ()
  "Skip per-call tool confirmation in this buffer until disabled.

This is blunt: it affects ALL tool calls in this buffer (read tools,
write tools, define_tool, and anything self-authored), not just a
specific one -- intended for short bursts of bulk work like scaffolding
a project, not as a permanent setting. Turn it back off with
`gptel-agent-approve-all-disable' when you're done. Buffer-local only;
does not persist across Emacs restarts or affect other buffers."
  (interactive)
  (setq gptel-agent--saved-confirm-tool-calls gptel-confirm-tool-calls)
  (setq-local gptel-confirm-tool-calls nil)
  (message "gptel-agent: ALL tool calls in %s will run WITHOUT confirmation. Call gptel-agent-approve-all-disable when done."
           (buffer-name)))

;;;###autoload
(defun gptel-agent-approve-all-disable ()
  "Restore normal per-call tool confirmation in this buffer."
  (interactive)
  (setq-local gptel-confirm-tool-calls
              (or gptel-agent--saved-confirm-tool-calls 'auto))
  (message "gptel-agent: tool call confirmation restored in %s" (buffer-name)))

(provide 'gptel-agent-approve-all)
;;; approve-all.el ends here
