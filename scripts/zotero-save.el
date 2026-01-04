;;; zotero-save.el --- Save URLs to Zotero via Translation Server -*- lexical-binding: t; -*-

;; Author: Your Name
;; Version: 1.0.0
;; Package-Requires: ((emacs "27.1") (request "0.3.2"))
;; Keywords: tools, bibliography, zotero
;; URL: https://github.com/junghan0611/zotero-config

;;; Commentary:

;; Save URLs to Zotero without leaving Emacs.
;; Uses the Zotero Translation Server to extract metadata
;; and the Zotero Web API to save items.
;;
;; Setup:
;;   1. Start Translation Server: docker run -d -p 1969:1969 zotero/translation-server
;;   2. Set your credentials:
;;      (setq zotero-api-key "your-api-key"
;;            zotero-user-id "your-user-id")
;;   3. Load this file: (load-file "path/to/zotero-save.el")
;;
;; Usage:
;;   M-x zotero-save-url RET <url> RET
;;   M-x zotero-save-url-at-point
;;   M-x zotero-save-org-link
;;
;; Doom Emacs:
;;   (map! :leader
;;         :desc "Save URL to Zotero" "n z u" #'zotero-save-url-at-point
;;         :desc "Save Org link to Zotero" "n z l" #'zotero-save-org-link)

;;; Code:

(require 'json)
(require 'url)
(require 'org nil t)  ; Optional Org-mode integration

;;; Customization

(defgroup zotero-save nil
  "Save URLs to Zotero via Translation Server."
  :group 'tools
  :prefix "zotero-")

(defcustom zotero-api-key nil
  "Zotero API key for authentication.
Get one at https://www.zotero.org/settings/keys"
  :type 'string
  :group 'zotero-save)

(defcustom zotero-user-id nil
  "Zotero user ID.
Find it at https://www.zotero.org/settings/keys"
  :type 'string
  :group 'zotero-save)

(defcustom zotero-translation-server "http://localhost:1969"
  "URL of the Zotero Translation Server."
  :type 'string
  :group 'zotero-save)

(defcustom zotero-default-collection nil
  "Default collection key to add items to.
Set to nil to add to library root."
  :type '(choice (const :tag "Library root" nil)
                 (string :tag "Collection key"))
  :group 'zotero-save)

(defcustom zotero-save-after-hook nil
  "Hook run after successfully saving an item to Zotero.
The hook functions receive two arguments: URL and ITEM-DATA."
  :type 'hook
  :group 'zotero-save)

;;; Internal variables

(defvar zotero--api-base "https://api.zotero.org"
  "Base URL for Zotero Web API.")

;;; Helper functions

(defun zotero--check-credentials ()
  "Check if Zotero credentials are configured."
  (unless zotero-api-key
    (user-error "Zotero API key not set. Set `zotero-api-key' or ZOTERO_API_KEY env var"))
  (unless zotero-user-id
    (user-error "Zotero user ID not set. Set `zotero-user-id' or ZOTERO_USER_ID env var")))

(defun zotero--get-api-key ()
  "Get Zotero API key from variable or environment."
  (or zotero-api-key
      (getenv "ZOTERO_API_KEY")))

(defun zotero--get-user-id ()
  "Get Zotero user ID from variable or environment."
  (or zotero-user-id
      (getenv "ZOTERO_USER_ID")))

(defun zotero--translation-server-available-p ()
  "Check if Translation Server is available."
  (condition-case nil
      (let ((url-request-method "GET"))
        (with-current-buffer (url-retrieve-synchronously
                              zotero-translation-server
                              nil nil 5)
          (prog1 t (kill-buffer))))
    (error nil)))

(defun zotero--fetch-metadata (url)
  "Fetch metadata for URL from Translation Server."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "text/plain")))
         (url-request-data url)
         (endpoint (concat zotero-translation-server "/web")))
    (with-current-buffer (url-retrieve-synchronously endpoint nil nil 30)
      (goto-char (point-min))
      (re-search-forward "^$")
      (let ((response (buffer-substring (1+ (point)) (point-max))))
        (kill-buffer)
        (condition-case nil
            (json-read-from-string response)
          (json-readtable-error
           ;; Fallback: create basic webpage item
           (zotero--create-fallback-item url)))))))

(defun zotero--create-fallback-item (url)
  "Create a fallback webpage item for URL."
  (let ((domain (url-host (url-generic-parse-url url))))
    (vector
     `((itemType . "webpage")
       (title . ,domain)
       (url . ,url)
       (accessDate . ,(format-time-string "%Y-%m-%dT%H:%M:%SZ" nil t))))))

(defun zotero--add-to-collection (metadata collection-key)
  "Add COLLECTION-KEY to METADATA items."
  (if collection-key
      (cl-map 'vector
              (lambda (item)
                (append item `((collections . [,collection-key]))))
              metadata)
    metadata))

(defun zotero--upload-item (metadata)
  "Upload METADATA to Zotero library."
  (let* ((url-request-method "POST")
         (url-request-extra-headers
          `(("Zotero-API-Key" . ,(zotero--get-api-key))
            ("Content-Type" . "application/json")))
         (url-request-data (json-encode metadata))
         (endpoint (format "%s/users/%s/items"
                           zotero--api-base
                           (zotero--get-user-id))))
    (with-current-buffer (url-retrieve-synchronously endpoint nil nil 30)
      (goto-char (point-min))
      (re-search-forward "^$")
      (let ((response (json-read-from-string
                       (buffer-substring (1+ (point)) (point-max)))))
        (kill-buffer)
        response))))

(defun zotero--extract-url-at-point ()
  "Extract URL at point, handling Org links."
  (or (thing-at-point 'url t)
      (when (and (derived-mode-p 'org-mode)
                 (fboundp 'org-element-context))
        (let ((element (org-element-context)))
          (when (eq (org-element-type element) 'link)
            (org-element-property :raw-link element))))
      (when (region-active-p)
        (buffer-substring-no-properties (region-beginning) (region-end)))))

;;; Interactive commands

;;;###autoload
(defun zotero-save-url (url &optional collection-key)
  "Save URL to Zotero library.
If COLLECTION-KEY is provided, add item to that collection."
  (interactive
   (list (read-string "URL: " (zotero--extract-url-at-point))
         (when current-prefix-arg
           (read-string "Collection key (empty for root): " nil nil nil))))
  (zotero--check-credentials)

  (unless (zotero--translation-server-available-p)
    (user-error "Translation Server not available at %s. Start it with: docker run -d -p 1969:1969 zotero/translation-server"
                zotero-translation-server))

  (message "Fetching metadata for %s..." url)
  (let* ((metadata (zotero--fetch-metadata url))
         (collection (or collection-key zotero-default-collection))
         (metadata-with-collection (zotero--add-to-collection metadata collection)))

    (message "Uploading to Zotero...")
    (let ((response (zotero--upload-item metadata-with-collection)))
      (let-alist response
        (let ((success-count (length .successful))
              (failed-count (length .failed)))
          (if (> success-count 0)
              (progn
                (message "Successfully saved %d item(s) to Zotero!" success-count)
                (run-hook-with-args 'zotero-save-after-hook url metadata))
            (message "Failed to save item(s): %s" .failed)))))))

;;;###autoload
(defun zotero-save-url-at-point ()
  "Save URL at point to Zotero.
In Org-mode, also handles Org links."
  (interactive)
  (let ((url (zotero--extract-url-at-point)))
    (if url
        (zotero-save-url url)
      (call-interactively #'zotero-save-url))))

;;;###autoload
(defun zotero-save-org-link ()
  "Save the Org link at point to Zotero.
Must be called in an Org buffer with point on a link."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (let ((element (org-element-context)))
    (if (eq (org-element-type element) 'link)
        (zotero-save-url (org-element-property :raw-link element))
      (user-error "No link at point"))))

;;;###autoload
(defun zotero-save-clipboard ()
  "Save URL from clipboard/kill-ring to Zotero."
  (interactive)
  (let ((url (or (gui-get-selection 'CLIPBOARD)
                 (car kill-ring))))
    (if (and url (string-match-p "^https?://" url))
        (zotero-save-url url)
      (user-error "No URL in clipboard"))))

;;;###autoload
(defun zotero-check-server ()
  "Check if Translation Server is running."
  (interactive)
  (if (zotero--translation-server-available-p)
      (message "Translation Server is running at %s" zotero-translation-server)
    (message "Translation Server NOT available at %s" zotero-translation-server)))

;;; Doom Emacs integration
(with-eval-after-load 'doom
  (map! :leader
        (:prefix-map ("n" . "notes")
         (:prefix ("z" . "zotero")
          :desc "Save URL to Zotero" "u" #'zotero-save-url
          :desc "Save URL at point" "p" #'zotero-save-url-at-point
          :desc "Save Org link" "l" #'zotero-save-org-link
          :desc "Save clipboard URL" "c" #'zotero-save-clipboard
          :desc "Check server" "s" #'zotero-check-server))))

(provide 'zotero-save)
;;; zotero-save.el ends here
