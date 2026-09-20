;;; skills.el --- Pick up on Claude/Agents-style "skills" -*- lexical-binding: t; -*-

;; Supports the common agent-CLI convention of a directory tree:
;;   ~/.agents/skills/<skill-name>/SKILL.md
;; with YAML frontmatter (name, description) followed by free-form
;; instructions. Never auto-injected; pull one in with "@name" (goes
;; through context-at-refs.el's @ref expansion) or
;; `gptel-agent-insert-skill' (C-c C-a).

(require 'gptel)
(require 'project)
(require 'cl-lib)
;; `gptel-agent-at-ref-resolvers' and `gptel-agent--truncate' are
;; defined in context-at-refs.el / tools-read.el, both loaded before
;; this file by core/init.el.
(declare-function gptel-agent--truncate "tools-read")
(defvar gptel-agent-at-ref-resolvers)

(defvar gptel-agent-skills-directories
  (list (expand-file-name "~/.agents/skills/"))
  "List of directories to search for skills, each expected to contain
one subdirectory per skill named <skill-name>/SKILL.md. Checked in
order; earlier entries win on name collisions. A project-local
\".agents/skills/\" directory (if the current buffer is inside a
project) is always checked first, ahead of this list.")

(defun gptel-agent--skills-search-path ()
  "Return the full ordered list of skill directories to search: a
project-local .agents/skills/ (if any) first, then
`gptel-agent-skills-directories'."
  (let* ((proj (project-current))
         (proj-skills (and proj (expand-file-name ".agents/skills/" (project-root proj)))))
    (append (and proj-skills (file-directory-p proj-skills) (list proj-skills))
            (seq-filter #'file-directory-p gptel-agent-skills-directories))))

(defun gptel-agent--skill-dirs ()
  "Return an alist of (skill-name . SKILL.md-path) for every skill
found under `gptel-agent--skills-search-path', first match wins."
  (let ((seen (make-hash-table :test 'equal))
        (result nil))
    (dolist (root (gptel-agent--skills-search-path))
      (dolist (entry (ignore-errors (directory-files root t "^[^.]")))
        (when (file-directory-p entry)
          (let* ((name (file-name-nondirectory (directory-file-name entry)))
                 (skill-file (expand-file-name "SKILL.md" entry)))
            (when (and (file-exists-p skill-file) (not (gethash name seen)))
              (puthash name t seen)
              (push (cons name skill-file) result))))))
    (nreverse result)))

(defun gptel-agent--skill-frontmatter (skill-file)
  "Parse the leading YAML-ish frontmatter (between --- lines) of
SKILL-FILE into an alist of (key . value) strings. Best-effort, plain
line-based parsing -- good enough for the simple `key: value' and
`key: >' folded-scalar forms these files use; does not attempt real
YAML parsing."
  (with-temp-buffer
    (insert-file-contents skill-file)
    (goto-char (point-min))
    (let (result)
      (when (looking-at-p "^---$")
        (forward-line 1)
        (let ((start (point)))
          (when (re-search-forward "^---$" nil t)
            (let ((body (buffer-substring-no-properties start (match-beginning 0)))
                  (key nil) (val nil))
              (dolist (line (split-string body "\n"))
                (cond
                 ((string-match "^\\([a-zA-Z_-]+\\):[ \t]*\\(.*\\)$" line)
                  (when key (push (cons key (string-trim val)) result))
                  (setq key (match-string 1 line))
                  (setq val (match-string 2 line)))
                 (key (setq val (concat val " " (string-trim line))))))
              (when key (push (cons key (string-trim val)) result))))))
      (nreverse result))))

(defun gptel-agent--skill-body (skill-file)
  "Return SKILL-FILE's contents after the closing --- of its
frontmatter (or the whole file, if it has none)."
  (with-temp-buffer
    (insert-file-contents skill-file)
    (goto-char (point-min))
    (if (looking-at-p "^---$")
        (progn (forward-line 1)
               (if (re-search-forward "^---$" nil t)
                   (progn (forward-line 1)
                          (buffer-substring-no-properties (point) (point-max)))
                 (buffer-string)))
      (buffer-string))))

(defun gptel-agent--resolve-skill-ref (ref)
  "Resolver for `gptel-agent-at-ref-resolvers': if REF names a known
skill, return its full file contents (frontmatter + body); else nil."
  (when-let* ((entry (assoc ref (gptel-agent--skill-dirs))))
    (with-temp-buffer
      (insert-file-contents (cdr entry))
      (buffer-string))))

(add-to-list 'gptel-agent-at-ref-resolvers #'gptel-agent--resolve-skill-ref t)

;;;###autoload
(defun gptel-agent-insert-skill ()
  "Interactively pick a skill (fuzzy-searchable by name and
description) and insert \"@name \" at point, the same @ref syntax
`context-at-refs.el' already expands -- so the model receives the
skill's full SKILL.md body when this prompt is sent. Meant to be bound
to a key in `gptel-mode-map', e.g.:
  (define-key gptel-mode-map (kbd \"C-c C-a\") #\\='gptel-agent-insert-skill)"
  (interactive)
  (let* ((skills (gptel-agent--skill-dirs)))
    (if (null skills)
        (message "gptel-agent: no skills found under %s"
                 (mapconcat #'identity (gptel-agent--skills-search-path) ", "))
      (let* ((candidates
              (mapcar (lambda (entry)
                        (let* ((name (car entry))
                               (fm (gptel-agent--skill-frontmatter (cdr entry)))
                               (desc (or (cdr (assoc "description" fm)) "")))
                          (cons (format "%-28s %s"
                                        (propertize name 'face 'font-lock-keyword-face)
                                        (propertize desc 'face 'font-lock-comment-face))
                                name)))
                      skills))
             (choice (completing-read "Skill: " candidates nil t))
             (name (cdr (assoc choice candidates))))
        (when name
          (insert (format "@%s " name)))))))

(provide 'gptel-agent-skills)

;; Bind directly into gptel-mode-map so it's available in any gptel
;; buffer without further setup. Chosen to mirror gptel's own
;; conventions (C-c C-c send etc.) and avoid clashing with anything
;; already bound there.
(define-key gptel-mode-map (kbd "C-c C-a") #'gptel-agent-insert-skill)

;;; skills.el ends here
