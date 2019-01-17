;;; telega.el --- Telegram client (unofficial)

;; Copyright (C) 2016-2019 by Zajcev Evgeny

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Created: Wed Nov 30 19:04:26 2016
;; Keywords:
;; Version: 0.3.0
(defconst telega-version "0.3.0")
(defconst telega-tdlib-min-version "1.3.0")

;; telega is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; telega is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with telega.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(require 'password-cache)               ; `password-read'
(require 'cl-lib)

(require 'telega-customize)
(require 'telega-server)
(require 'telega-root)
(require 'telega-ins)
(require 'telega-filter)
(require 'telega-chat)
(require 'telega-info)
(require 'telega-media)
(require 'telega-util)

(defconst telega-app '(72239 . "bbf972f94cc6f0ee5da969d8d42a6c76"))

(defun telega--create-hier ()
  "Ensure directory hier is valid."
  (ignore-errors
    (mkdir telega-directory))
  (ignore-errors
    (mkdir telega-cache-dir)))

;;;###autoload
(defun telega ()
  "Start telegramming."
  (interactive)
  (telega--create-hier)

  (unless (process-live-p (telega-server--proc))
    ;; NOTE: for telega-server restarts also recreate root buffer,
    ;; killing root buffer also cleanup all chat buffers and stops any
    ;; timers used for animation
    (when (buffer-live-p (telega-root--buffer))
      (kill-buffer (telega-root--buffer)))

    (telega-server--start))

  (unless (buffer-live-p (telega-root--buffer))
    (with-current-buffer (get-buffer-create telega-root-buffer-name)
      (telega-root-mode)))

  (pop-to-buffer-same-window telega-root-buffer-name))

;;;###autoload
(defun telega-kill (force)
  "Kill currently running telega.
With prefix arg force quit without confirmation."
  (interactive "P")
  (let* ((chat-count (length telega--chat-buffers))
         (suffix (cond ((eq chat-count 0) "")
                       ((eq chat-count 1) (format " (and 1 chat buffer)"))
                       (t (format " (and all %d chat buffers)" chat-count)))))
    (when (or force (y-or-n-p (concat "Kill telega" suffix "? ")))
      (kill-buffer telega-root-buffer-name))))

(defun telega-logout ()
  "Switch to another telegram account."
  (interactive)
  (telega-server--send `(:@type "logOut")))

(defun telega--setTdlibParameters ()
  "Sets the parameters for TDLib initialization."
  (telega-server--send
   (list :@type "setTdlibParameters"
         :parameters (list :@type "tdlibParameters"
                           :use_test_dc (or telega-use-test-dc :false)
                           :database_directory telega-directory
                           :files_directory telega-cache-dir
                           :use_file_database telega-use-file-database
                           :use_chat_info_database telega-use-chat-info-database
                           :use_message_database telega-use-message-database
                           :use_secret_chats t
                           :api_id (car telega-app)
                           :api_hash (cdr telega-app)
                           :system_language_code telega-language
                           :device_model "Emacs"
                           :system_version emacs-version
                           :application_version telega-version
                           :enable_storage_optimizer t
                           :ignore_file_names :false
                           )))

  ;; List of proxies, since tdlib 1.3.0
  (dolist (proxy telega-proxies)
    (telega-server--send
     `(:@type "addProxy" ,@proxy)))
  )

(defun telega--checkDatabaseEncryptionKey ()
  "Set database encryption key, if any."
  ;; NOTE: database encryption is disabled
  ;;   consider encryption as todo in future
  (telega-server--send
   (list :@type "checkDatabaseEncryptionKey"
         :encryption_key ""))

  ;; Set proxy here, so registering phone will use it
  ;; DEPRECATED, use `telega-proxies'
  (when telega-socks5-proxy
    (telega-server--send
     (list :@type "setProxy"
           :proxy `(:@type "proxySocks5"
                           ,@telega-socks5-proxy)))))

(defun telega--setAuthenticationPhoneNumber (&optional phone-number)
  "Sets the phone number of the user."
  (let ((phone (or phone-number (read-string "Telega phone number: " "+"))))
    (telega-server--send
     (list :@type "setAuthenticationPhoneNumber"
           :phone_number phone
           :allow_flash_call :false
           :is_current_phone_number :false))))

(defun telega-resend-auth-code ()
  "Resend auth code.
Works only if current state is `authorizationStateWaitCode'."
  (interactive)
  (telega-server--send
   (list :@type "resendAuthenticationCode")))

(defun telega--checkAuthenticationCode (registered-p &optional auth-code)
  "Send login auth code."
  (let ((code (or auth-code (read-string "Telega login code: ")))
        ;; NOTE: first_name is required for newly registered accounts
        (first-name (or (and registered-p "")
                        (read-from-minibuffer "First Name: "))))
    (telega-server--send
     (list :@type "checkAuthenticationCode"
           :code code
           :first_name first-name
           :last_name ""))))

(defun telega--checkAuthenticationPassword (auth-state &optional password)
  "Check the password for the 2-factor authentification."
  (let* ((hint (plist-get auth-state :password_hint))
         (pswd (or password
                   (password-read
                    (concat "Telegram password"
                            (if (string-empty-p hint)
                                ""
                              (format "(hint='%s')" hint))
                            ": ")))))
    (telega-server--send
     (list :@type "checkAuthenticationPassword"
           :password pswd))))

(defun telega--setOptions (&optional options-plist)
  "Send custom options from `telega-options-plist' to server."
  (cl-loop for (prop-name value) on (or options-plist telega-options-plist)
           by 'cddr
           do (telega-server--send
               (list :@type "setOption"
                     :name (substring (symbol-name prop-name) 1) ; strip `:'
                     :value (list :@type (cond ((memq value '(t nil))
                                                "optionValueBoolean")
                                               ((integerp value)
                                                "optionValueInteger")
                                               ((stringp value)
                                                "optionValueString"))
                                  :value (or value :false))))))

(defun telega--authorization-ready ()
  "Called when tdlib is ready to receive queries."
  (setq telega--me-id (plist-get telega--options :my_id))
  (cl-assert telega--me-id)

  (telega--setOptions)

  ;; Validate tdlib version
  (when (string< (plist-get telega--options :version)
                 telega-tdlib-min-version)
    (error (concat "TDLib version=%s < %s (min required), "
                   "please upgrade TDLib and recompile `telega-server'")
           (plist-get telega--options :version)
           telega-tdlib-min-version))

  ;; All OK, request for chats/users/etc
  (telega-status--set nil "Fetching chats...")
  (telega--getChats)

  (run-hooks 'telega-ready-hook))

(defun telega--authorization-closed ()
  (telega-server-kill)
  (run-hooks 'telega-closed-hook))

(defun telega--on-updateConnectionState (event)
  "Update telega connection state."
  (let* ((conn-state (plist-get (plist-get event :state) :@type))
         (status (substring conn-state 15)))
    (telega-status--set status)))

(defun telega--on-updateOption (event)
  "Proceed with option update from telega server."
  (setq telega--options
        (plist-put telega--options
                   (intern (concat ":" (plist-get event :name)))
                   (plist-get (plist-get event :value) :value))))

(defun telega--on-updateAuthorizationState (event)
  (let* ((state (plist-get event :authorization_state))
         (stype (plist-get state :@type)))
    (telega-status--set (concat "Auth " (substring stype 18)))
    (cl-ecase (intern stype)
      (authorizationStateWaitTdlibParameters
       (telega--setTdlibParameters))

      (authorizationStateWaitEncryptionKey
       (telega--checkDatabaseEncryptionKey))

      (authorizationStateWaitPhoneNumber
       (telega--setAuthenticationPhoneNumber))

      (authorizationStateWaitCode
       (telega--checkAuthenticationCode (plist-get state :is_registered)))

      (authorizationStateWaitPassword
       (telega--checkAuthenticationPassword state))

      (authorizationStateReady
       ;; TDLib is now ready to answer queries
       (telega--authorization-ready))

      (authorizationStateLoggingOut
       )

      (authorizationStateClosing
       )

      (authorizationStateClosed
       (telega--authorization-closed)))))

(defun telega--on-ok (event)
  "On ok result from command function call."
  ;; no-op
  )

(defun telega--getProxies ()
  "Return list of currently registered proxies."
  (let ((reply (telega-server--call (list :@type "getProxies"))))
    (mapcar #'identity (plist-get reply :proxies))))

(defun telega--pingProxies (proxies &optional callback)
  "Update ping stats for the PROXIES.
Call CALLBACK on updates."
  (let ((track-timeout nil))
    (cl-dolist (proxy proxies)
      (let* ((proxy-id (plist-get proxy :id))
             (ping (assq proxy-id telega--proxy-pings))
             (currts (time-to-seconds)))
        (when (> currts (+ (or (cadr ping) 0) 60))
          (setq track-timeout t)
          (setq telega--proxy-pings
                (put-alist proxy-id (cons currts nil)
                           telega--proxy-pings))
          (telega-server--call
           (list :@type "pingProxy" :proxy_id proxy-id)
           `(lambda (seconds)
              (setq telega--proxy-pings
                    (put-alist ,proxy-id (cons (time-to-seconds)
                                               (plist-get seconds :seconds))
                               telega--proxy-pings))
              (when ,callback
                (funcall ,callback)))))))

    (when (and track-timeout callback)
      ;; to track ping timeouts
      (run-with-timer 10 nil callback))))

(defun telega--enableProxy (proxy)
  (telega-server--call
   (list :@type "enableProxy"
         :proxy_id (plist-get proxy :id))))

(defun telega--disableProxy ()
  (telega-server--call
   (list :@type "disableProxy")))

(defun telega-proxy-last-used (&optional proxies)
  "Return last time used proxy."
  (car (cl-sort (or (copy-list proxies) (telega--getProxies))
                '> :key (telega--tl-prop :last_used_date))))

(defun telega-proxy-enabled (&optional proxies)
  "Return enable proxy from PROXIES list."
  (cl-find t (or proxies (telega--getProxies))
           :test 'eq :key (telega--tl-prop :is_enabled)))

(defun telega-version (&optional interactive-p)
  "Return telega (and tdlib) version.
If called interactively, then print version into echo area."
  (interactive "p")
  (let* ((tdlib-version (plist-get telega--options :version))
         (version (concat "telega v"
                          telega-version
                          " ("
                          (if tdlib-version
                              (concat "TDLib version " tdlib-version)
                            "TDLib version unknown, server not running")
                          ")")))
    (if interactive-p
        (message version)
      version)))

(provide 'telega)

;; run load-time hooks
(run-hooks 'telega-load-hook)

;;; telega.el ends here
