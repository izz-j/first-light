(asdf:defsystem #:gear
  :description "An experimental game engine."
  :author ("Michael Fiano <michael.fiano@gmail.com>"
           "Peter Keller <psilord@cs.wisc.edu>")
  :maintainer ("Michael Fiano <michael.fiano@gmail.com>"
               "Peter Keller <psilord@cs.wisc.edu>")
  :license "MIT"
  :homepage "https://github.com/hackertheory/gear"
  :bug-tracker "https://github.com/hackertheory/gear/issues"
  :source-control (:git "git@github.com:hackertheory/gear.git")
  :version "0.1.0"
  :encoding :utf-8
  :long-description #.(uiop:read-file-string
                       (uiop/pathname:subpathname *load-pathname* "README.md"))
  :depends-on (#:alexandria
               #:sdl2
               #:sdl2kit
               #:gamebox-math
               #:gamebox-frame-manager)
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "utils")
   (:file "extensions")
   (:file "actor")
   (:file "components")
   (:file "core-state")
   (:file "settings")
   (:file "call-flow")
   (:file "type-dag")
   (:file "scene")
   (:file "render")
   (:file "input")
   (:file "test")

   ;; core components
   (:module "components/basis"
    :components
    ((:file "basis")))
   (:module "components/camera"
    :components
    ((:file "camera")))
   (:module "components/tags"
    :components
    ((:file "tags")))
   (:module "components/transform"
    :components
    ((:file "state")
     (:file "transform")))))
