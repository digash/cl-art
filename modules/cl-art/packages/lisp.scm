(define-module (cl-art packages lisp)
  #:use-module ((gnu packages cpp) #:select (c2ffi))
  #:use-module ((gnu packages lisp-xyz)
                #:select (sbcl-cffi
                          sbcl-cl-autowrap
                          sbcl-dexador
                          sbcl-quri
                          sbcl-sdl2
                          sbcl-sdl2-image
                          sbcl-sdl2-ttf
                          sbcl-shasht))
  #:use-module ((gnu packages sdl) #:select (sdl2))
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (sbcl-cl-autowrap-with-c2ffi
            rewrite-art-lisp-inputs
            %cl-art-lisp-packages))

;;; Guix's sbcl-cl-autowrap builds the cl-autowrap/libffi system, whose
;;; C-INCLUDE form invokes c2ffi, but does not include c2ffi in the build
;;; environment.
(define-public sbcl-cl-autowrap-with-c2ffi
  (package
    (inherit sbcl-cl-autowrap)
    (native-inputs
     (modify-inputs (package-native-inputs sbcl-cl-autowrap)
       (prepend c2ffi)))
    (arguments
     (substitute-keyword-arguments (package-arguments sbcl-cl-autowrap)
       ((#:phases phases #~%standard-phases)
        #~(modify-phases #$phases
            (add-after 'fix-paths 'fix-libffi-include
              (lambda* (#:key inputs #:allow-other-keys)
                (substitute* "autowrap-libffi/autowrap.lisp"
                  (("/usr/lib64/libffi-3.2.1/include")
                   (dirname
                    (search-input-file inputs "/include/ffi.h"))))))))))))

(define %cl-autowrap-with-c2ffi-rewrite
  (package-input-rewriting/spec
   `(("sbcl-cl-autowrap" .
      ,(const sbcl-cl-autowrap-with-c2ffi)))))

;; Each SDL wrapper also expands C-INCLUDE while it is being built.  A native
;; input on cl-autowrap does not propagate into those separate build
;; environments, so add c2ffi to each wrapper in dependency order.  Delete the
;; checked-in specs first: the Linux specs shipped by cl-sdl2-image contain
;; constants and enums but no function declarations, so Autowrap otherwise
;; accepts them and leaves every IMG_* entry point undefined.  c2ffi must also
;; search SDL2's nested include directory: SDL_image.h and SDL_ttf.h include
;; headers such as SDL.h by basename, while Guix exposes them below
;; include/SDL2.
(define (with-c2ffi p)
  (package
    (inherit p)
    (native-inputs
     (modify-inputs (package-native-inputs p)
       (prepend c2ffi sdl2)))
    (arguments
     (substitute-keyword-arguments (package-arguments p)
       ((#:phases phases #~%standard-phases)
        #~(modify-phases #$phases
            (add-after 'unpack 'regenerate-autowrap-specs
              (lambda _
                ;; Dependency declarations have Guix store paths rather than
                ;; /usr/include paths.  Keep them out of the generated wrapper;
                ;; :include-sources in each upstream file retains its own SDL
                ;; add-on header.
                (substitute* "src/autowrap.lisp"
                  (("\"/usr/include/\"")
                   "\"/usr/include/\" \"/include/\""))
                (for-each delete-file
                          (find-files "src/spec" "\\.spec$"))))
            (add-before 'build 'find-sdl2-headers
              (lambda _
                (setenv
                 "C_INCLUDE_PATH"
                 (string-append
                  #$(this-package-native-input "sdl2") "/include/SDL2:"
                  (or (getenv "C_INCLUDE_PATH") "")))))
            (add-after 'build 'validate-autowrap-specs
              (lambda* (#:key outputs #:allow-other-keys)
                (let ((specs
                       (find-files (assoc-ref outputs "out") "\\.spec$")))
                  (unless (pair? specs)
                    (error "Autowrap generated no specs"))
                  (apply invoke "grep" "--quiet" "\"tag\": \"function\""
                         specs))))))))))

(define (with-c2ffi-and-ttf-header p)
  (let ((p (with-c2ffi p)))
    (package
      (inherit p)
      (arguments
       (substitute-keyword-arguments (package-arguments p)
         ((#:phases phases #~%standard-phases)
          #~(modify-phases #$phases
              (add-after 'unpack 'provide-autowrap-header
                (lambda _
                  (unless (file-exists? "src/spec/SDL2_ttf.h")
                    (copy-file "src/spec/SDL_ttf.h"
                               "src/spec/SDL2_ttf.h")))))))))))

(define %sdl2-addons-with-c2ffi-rewrite
  (package-input-rewriting/spec
   `(("sbcl-sdl2-image" . ,with-c2ffi)
     ("sbcl-sdl2-ttf" . ,with-c2ffi-and-ttf-header))))

(define-public (rewrite-art-lisp-inputs package)
  (%sdl2-addons-with-c2ffi-rewrite
   (%cl-autowrap-with-c2ffi-rewrite package)))

;; ART loads six ASDF systems, and CFFI is included explicitly so the profile
;; exposes both its sources and Guix-built FASLs.  Walk normal and propagated
;; package inputs exactly as the former Home configuration did, retaining only
;; SBCL packages for profile composition.  Native build inputs (including the
;; c2ffi repairs above) remain attached to the rewritten packages themselves.
(define-public %cl-art-lisp-packages
  (let loop ((pending
              (map rewrite-art-lisp-inputs
                   (list sbcl-cffi
                         sbcl-dexador
                         sbcl-quri
                         sbcl-sdl2
                         sbcl-sdl2-image
                         sbcl-sdl2-ttf
                         sbcl-shasht)))
             (seen '()))
    (if (null? pending)
        (filter (lambda (package)
                  (string-prefix? "sbcl-" (package-name package)))
                seen)
        (let ((package (car pending)))
          (if (memq package seen)
              (loop (cdr pending) seen)
              (loop (append
                     (filter-map
                      (lambda (input)
                        (and (package? (cadr input)) (cadr input)))
                      (append (package-inputs package)
                              (package-propagated-inputs package)))
                     (cdr pending))
                    (cons package seen)))))))
