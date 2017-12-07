(in-package :fl.comp.stub-0)

(define-component stub-0 ()
  (value 42))

(defmethod initialize-component ((component stub-0) (context context))
  (format t "fl.comp.stub-0:initialize-component called: ~A~%"
          (value component)))
