(define-module (cl-art packages art)
  #:use-module (cl-art packages lisp)
  #:use-module ((gnu packages bash) #:select (bash-minimal))
  #:use-module ((gnu packages lisp) #:select (sbcl))
  #:use-module (guix build-system copy)
  #:use-module (guix gexp)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (guix packages)
  #:use-module (guix utils)
  #:use-module (ice-9 rdelim)
  #:export (cl-art))

;; Resolve the repository root from this module's location in the channel load
;; path.  Relative local-file paths are otherwise resolved against the Guix
;; command's working directory and fail when the channel is used elsewhere.
(define %channel-root
  (let ((module-file
         (search-path %load-path "cl-art/packages/art.scm")))
    (unless module-file
      (error "cannot locate the cl-art channel checkout"))
    (canonicalize-path
     (string-append (dirname module-file) "/../../.."))))

(define-public cl-art
  (package
    (name "cl-art")
    (version
     (call-with-input-file (string-append %channel-root "/VERSION")
       read-line))
    ;; macOS uses the repository's native bootstrap; this Guix package carries
    ;; the repaired Linux SDL/Common Lisp dependency graph.
    (supported-systems '("x86_64-linux" "aarch64-linux"))
    (source
     (local-file (string-append %channel-root "/bin/art") "art"))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'(("art" "libexec/cl-art/art.lisp"))
      #:strip-binaries? #f
      #:validate-runpath? #f
      #:phases
      #~(modify-phases %standard-phases
          (add-before 'patch-source-shebangs 'make-guix-script-source
            (lambda _
              (substitute* "art"
                (("^#!.*")
                 ";; Invoked by the Guix package launcher."))))
          ;; Keep the portable env -S source byte-for-byte identical for
          ;; macOS, but do not expose it as an executable in the Guix output.
          ;; Guix's shebang patcher otherwise mistakes -S for an interpreter
          ;; and warns even though the command runs correctly.
          (add-after 'install 'install-launcher
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (script (string-append out "/libexec/cl-art/art.lisp"))
                     (launcher (string-append out "/bin/art")))
                (mkdir-p (dirname launcher))
                (call-with-output-file launcher
                  (lambda (port)
                    (format port "#!~a/bin/bash\n" #$bash-minimal)
                    (format port
                            (string-append
                             "exec ~a/bin/sbcl --dynamic-space-size 4096 "
                             "--script ~s \"$@\"\n")
                            #$sbcl script)))
                (chmod launcher #o555)))))))
    (inputs (list bash-minimal))
    ;; ART discovers Guix-provided ASDF systems by scanning the active profile.
    ;; Propagation is intentional: ordinary inputs would be retained in the store
    ;; closure but would not be linked into that profile's Common Lisp trees.
    (propagated-inputs
     (cons sbcl %cl-art-lisp-packages))
    (home-page "https://github.com/digash/cl-art")
    (synopsis "Fetch and display public-domain artwork")
    (description
     "CL-ART downloads public-domain works from the Art Institute of Chicago
and displays a static, fullscreen image on every connected monitor until a key
is pressed or the mouse moves.  It uses Common Lisp and SDL2 and deliberately
does not pan, zoom, rotate, or otherwise animate the images.")
    (license license:expat)))
