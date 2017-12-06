(asdf:defsystem #:first-light-example
  :description "Example scene for First Light."
  :author ("Michael Fiano <michael.fiano@gmail.com>"
           "Peter Keller <psilord@cs.wisc.edu>")
  :maintainer ("Michael Fiano <michael.fiano@gmail.com>"
               "Peter Keller <psilord@cs.wisc.edu>")
  :license "MIT"
  :homepage "https://github.com/hackertheory/first-light"
  :bug-tracker "https://github.com/hackertheory/first-light/issues"
  :source-control (:git "git@github.com:hackertheory/first-light.git")
  :version "0.1.0"
  :encoding :utf-8
  :long-description #.(uiop:read-file-string
                       (uiop/pathname:subpathname *load-pathname* "README.md"))
  :depends-on (#:alexandria
               #:gamebox-math
               #:first-light
               #:glkit
               #:cl-opengl
	       #:defpackage-plus)
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "components/stub-0/package")
   (:file "input")
   (:file "components/stub-0/stub-0")
   (:file "components/gun/gun")
   (:file "components/gun-manager/gun-manager")
   (:file "components/hit-points/hit-points")))
