;;; telega-webpage.el --- Webpage viewer

;; Copyright (C) 2019 by Zajcev Evgeny.

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Created: Tue Jan  8 15:27:03 2019
;; Keywords:

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
(require 'cl-lib)

(define-button-type 'telega-instant-view
  :supertype 'telega
  :inserter 'telega-ins--instant-view
  :button-props-func 'telega-instant-view-button--props
  'action #'telega-instant-view-button--action
  'face 'telega-link)

(defun telega-ins--instant-view (iview)
  "IVIEW is cons of URL and SITENAME."
  (telega-ins "[ " telega-symbol-thunder
              ;; I18N: ???
              " INSTANT VIEW "
              " ]")
  )

(defun telega--getWebPageInstantView (url &optional partial)
  (telega-server--call
   (list :@type "getWebPageInstantView"
         :url url
         :force_full (or (not partial) :false))))

(defvar telega-webpage--url nil
  "URL for the instant view webpage currently viewing.")
(make-variable-buffer-local 'telega-webpage--url)

(defvar telega-webpage--sitename nil
  "Sitename for the webpage currently viewing.")
(make-variable-buffer-local 'telega-webpage--sitename)

(defcustom telega-webpage-header-line-format
  '(" " (:eval (concat telega-webpage--sitename
                       (and telega-webpage--sitename ": ")
                       telega-webpage--url)))
  "Header line format for instant webpage."
  :type 'list
  :group 'telega)

(defvar telega-webpage-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "g" 'telega-webpage-browse-url)
    (define-key map "w" 'telega-webpage-browse-url)
    (define-key map [?\t] 'telega-button-forward)
    (define-key map "\e\t" 'telega-button-backward)
    (define-key map [backtab] 'telega-button-backward)
    map))

(define-derived-mode telega-webpage-mode special-mode "Telega-WebPage"
  "The mode for instant viewing webpages in telega.
Keymap:
\\{telega-webpage-mode-map}"
  :group 'telega
  (setq header-line-format telega-webpage-header-line-format)
  (set-buffer-modified-p nil))

(defun telega-webpage-browse-url (url)
  "Browse URL with web browser."
  (interactive (list telega-webpage--url))
  (browse-url url))

(defun telega-webpage--ins-rt (rt &optional strip-nl)
  "Insert RichText RT.
If STRIP-NL is non-nil then strip leading/trailing newlines."
  (cl-ecase (telega--tl-type rt)
    (richTextPlain
     (telega-ins (funcall (if strip-nl 'telega-strip-newlines 'identity)
                          (plist-get rt :text))))
    (richTexts
     (mapc (lambda (richtext)
             (telega-webpage--ins-rt richtext strip-nl))
           (plist-get rt :texts)))
    (richTextBold
     (telega-ins--with-attrs (list :face 'bold)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))
    (richTextItalic
     (telega-ins--with-attrs (list :face 'italic)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))
    (richTextUnderline
     (telega-ins--with-attrs (list :face 'underline)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))
    (richTextStrikethrough
     (telega-ins--with-attrs (list :face 'telega-webpage-strike-through)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))
    (richTextFixed
     (telega-ins--with-attrs (list :face 'fixed-pitch)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))
    (richTextUrl
     (let ((url (plist-get rt :url)))
       (telega-ins--raw-button (nconc (list :help-echo (concat "URL: " url))
                                      (telega-link-props 'url url 'link))
         (telega-webpage--ins-rt (plist-get rt :text) strip-nl))))
    (richTextEmailAddress
     (telega-ins--with-attrs (list :face 'link)
       (telega-webpage--ins-rt (plist-get rt :text) strip-nl)))))

(defun telega-webpage--ins-PageBlock (pb)
  "Render PageBlock BLK for the instant view."
  (cl-ecase (telega--tl-type pb)
    (pageBlockTitle
     (telega-ins--with-attrs (list :face 'telega-webpage-title
                                   :fill 'left
                                   :fill-column telega-webpage-fill-column)
       (telega-webpage--ins-rt (plist-get pb :title) 'strip-newlines)))
    (pageBlockSubtitle
     (telega-webpage--ins-rt (plist-get pb :subtitle)))
    (pageBlockAuthorDate
     (telega-ins "By ")
     (telega-webpage--ins-rt (plist-get pb :author))
     (telega-ins " • ")
     (telega-ins--date-full (plist-get pb :publish_date))
     (telega-ins "\n"))
    (pageBlockHeader
     (telega-ins--with-attrs (list :face 'telega-webpage-header
                                   :fill 'left
                                   :fill-column telega-webpage-fill-column)
       (telega-webpage--ins-rt (plist-get pb :header))))
    (pageBlockSubheader
     (telega-ins--with-attrs (list :face 'telega-webpage-subheader
                                   :fill 'left
                                   :fill-column telega-webpage-fill-column)
       (telega-webpage--ins-rt (plist-get pb :subheader))))
    (pageBlockParagraph
     (telega-ins--with-attrs (list :fill 'left
                                   :fill-column telega-webpage-fill-column)
       (telega-webpage--ins-rt (plist-get pb :text)))
     (telega-ins "\n"))
    (pageBlockPreformatted
     (telega-ins "<TODO: pageBlockPreformatted>"))
    (pageBlockFooter
     (telega-ins "<TODO: pageBlockFooter>"))
    (pageBlockDivider
     (telega-ins "---------"))
    (pageBlockAnchor
     )
    (pageBlockList
     (let ((orderedp (plist-get pb :is_ordered))
           (items (plist-get pb :items)))
       (dotimes (ordernum (length items))
         (let ((label (if orderedp (format "%d. " (1+ ordernum)) "• ")))
           (telega-ins--labeled label telega-webpage-fill-column
             (telega-webpage--ins-rt (aref items ordernum))))
         (telega-ins "\n"))))
    (pageBlockBlockQuote
     (telega-ins telega-symbol-vertical-bar)
     (telega-ins--with-attrs (list :fill 'left
                                   :fill-prefix telega-symbol-vertical-bar
                                   :fill-column telega-webpage-fill-column)
       (telega-webpage--ins-rt (plist-get pb :text)))
     (telega-ins "\n"))
    (pageBlockPullQuote
     (telega-ins "<TODO: pageBlockPullQuote>"))
    (pageBlockAnimation
     (telega-ins "<TODO: pageBlockAnimation>"))
    (pageBlockAudio
     (telega-ins "<TODO: pageBlockAudio>"))
    (pageBlockPhoto
     (telega-ins--photo (plist-get pb :photo))
     (telega-ins--with-attrs (list :face 'shadow)
       (telega-webpage--ins-rt (plist-get pb :caption))))
    (pageBlockVideo
     (telega-ins "<TODO: pageBlockVideo>"))
    (pageBlockCover
     (telega-webpage--ins-PageBlock (plist-get pb :cover)))
    (pageBlockEmbedded
     (telega-ins "<TODO: pageBlockEmbedded>"))
    (pageBlockEmbeddedPost
     (telega-ins "<TODO: pageBlockEmbeddedPost>"))
    (pageBlockCollage
     (telega-ins "<TODO: pageBlockCollage>"))
    (pageBlockSlideshow
     (telega-ins "<TODO: pageBlockSlideshow>"))
    (pageBlockChatLink
     (telega-ins "<TODO: pageBlockChatLink>"))
    )
  (unless (memq (telega--tl-type pb) '(pageBlockAnchor pageBlockCover))
    (telega-ins "\n"))
  )

(defun telega-webpage--instant-view (url &optional sitename)
  "Instantly view webpage by URL."
  (pop-to-buffer-same-window
   (get-buffer-create "*Telega Instant View*"))

  (let ((buffer-read-only nil)
        (instant-view (telega--getWebPageInstantView url)))
    (erase-buffer)
    (setq telega-webpage--url url
          telega-webpage--sitename sitename)
    (mapc 'telega-webpage--ins-PageBlock
          (plist-get (telega--getWebPageInstantView url) :page_blocks))

    (when telega-debug
      (telega-ins-fmt "\n---DEBUG---\n%S" instant-view))
    (goto-char (point-min)))

  (unless (eq major-mode 'telega-webpage-mode)
    (telega-webpage-mode))

  (message "Press `%s' to open in web browser"
           (substitute-command-keys "\\[telega-webpage-browse-url]")))

(provide 'telega-webpage)

;;; telega-webpage.el ends here
