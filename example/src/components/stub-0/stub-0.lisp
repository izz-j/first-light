(in-package :first-light-example.comp.stub-0)

(define-component stub-0 ()
  (value 84))

(defmethod initialize-component ((component stub-0) (context context))
  (format t "first-light-example.comp.stub-0:initialize-component called: ~A~%"
          (value component)))
