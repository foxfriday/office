;;; office.el --- Calendar and contacts management         -*- lexical-binding: t; -*-

;; Copyright (C) 2023 M. Rincón

;; Author: M. Rincón
;; Keywords: diary contacts calendar
;; Version: 0.0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; Sync local and remote contacts along with calendar events.

;;; Code:
(require 'calendar)
(require 'ecomplete)
(require 'icalendar)

(defvar office-calendar-dir "~/Calendar/calendars/"
  "Calendar directory.")

(defvar office-diary-file nil
  "Location of the import diary file, if nil use `diary-file`.")

(defvar office-diary-import-start ";;; start of imported calendar\n"
  "Text marking the start of the diary import.")

(defvar office-diary-import-end ";;; end of imported calendar\n"
  "Text marking the end of the diary import.")

(defvar office-sync-email-group nil
  "Email group to sync.")

(defun office-remove-imported-area ()
  "Remove the previously imported appointments."
  (goto-char (point-min))
  (let* ((pmin (search-forward office-diary-import-start nil t))
         (pmin (if pmin (- pmin (length office-diary-import-start)) nil))
         (pmax (search-forward office-diary-import-end nil t))
         (pmax (if pmax pmax (point-max)))
         (bkup nil))
    (if (and pmin pmax)
      (setq bkup (delete-and-extract-region pmin pmax)))
    bkup))

;;;###autoload
(defun office-update-local-contacts ()
  "Add local contacts using khard to `ecomplete`."
  (interactive)
  (let* ((khard "khard email --parsable --search-in-source-files --remove-first-line")
         (cntcs (split-string (shell-command-to-string khard) "\n")))
    (ecomplete-setup)
    (dolist-with-progress-reporter (row cntcs)
        "Updating contacts"
      (let* ((cntc (split-string row "\t"))
             (email (car-safe cntc))
             (name (if email (nth 1 cntc) nil))
             (group (if name (nth 2 cntc) nil))
             (addit (if office-sync-email-group (string= office-sync-email-group group) t)))
        (when (and addit email name)
          (ecomplete-add-item 'mail email (concat name " <" email ">")))))
    (ecomplete-save)))

;;;###autoload
(defun office-update-local-diary ()
  "Update diary file using `icalendar`."
  (interactive)
  (let* ((dfile (if office-diary-file office-diary-file diary-file))
         (dbuff (find-file-noselect dfile))
         (files (directory-files-recursively office-calendar-dir "\\.ics$")))
    (set-buffer dbuff)
    (office-remove-imported-area)
    (goto-char (point-max))
    (insert (concat "\n" office-diary-import-start))
    (when files
      (with-temp-buffer
        (dolist-with-progress-reporter (file files)
            "Updating calendar"
          (insert-file-contents file)
          (icalendar-import-buffer dfile t))))
    (goto-char (point-max))
    (insert office-diary-import-end)))

(defun office-update-sentinel (process event)
  "Wait for sync PROCESS to end before update and message EVENT."
  (when (memq (process-status process) '(exit signal))
    (message event)
    (office-update-local-contacts)
    (office-update-local-diary)))

;;;###autoload
(defun office-sync ()
  "Update calendar and contacts from remote server."
  (interactive)
  (let* ((log-buffer (get-buffer-create "*Messages*")))
    (make-process :name "vdirsyncer"
                  :buffer log-buffer
                  :command (list "vdirsyncer" "sync")
                  :stderr log-buffer
                  :sentinel 'office-update-sentinel)))

(provide 'office)
;;; office.el ends here
