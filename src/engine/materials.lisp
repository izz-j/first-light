(in-package :fl.core)

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; base types initially available for matvars:
;; :integer
;; :float
;; :vec2, :vec3, :vec4
;; :string
;; :var
;; :shader
;; :texture

;; Held in core-state, the material database for all materials everywhere.
;; THere is a better API to this than just raw hash tables.
(defclass materials-table ()
  ((%material-table :reader material-table
                    :initarg :material-table
                    :initform (make-hash-table))))

(defun make-materials-table (&rest init-args)
  (apply #'make-instance 'materials-table init-args))



(defclass material-value ()
  (;; This is the semantic value for a uniform. In the case of a :sampler-2d
   ;; it is a string to a texture found on disk, etc.
   (%semantic-value :accessor semantic-value
                    :initarg :semantic-value)
   ;; This is the processed value that is suitable to bind to a uniform.

   (%computed-value :accessor computed-value
                    :initarg :computed-value)
   ;; The function that knows how to bind this value to a shader.
   (%binder :accessor binder
            :initarg :binder)))

(defun make-material-value (&rest init-args)
  (apply #'make-instance 'material-value init-args))


(defclass material ()
  ((%id :reader id
        :initarg :id)
   ;; This backreference simplifies when we need to change the texture at
   ;; runtime or do something else that makes us grovel around in the
   ;; core-state.
   (%core-state :reader core-state
                :initarg :core-state)
   ;; This is the shader NAME
   (%shader :reader shader
            :initarg :shader)
   (%uniforms :reader uniforms
              :initarg :uniforms
              ;; key is a uniform keyword, value is material-value
              :initform (make-hash-table))
   (%blocks :reader blocks
            :initarg :blocks
            ;; key is a block keyword, value is material-value
            :initform (make-hash-table))
   (%active-texture-unit :accessor active-texture-unit
                         :initarg :active-texture-unit
                         :initform 0)
   (%source-form :reader source-form
                 :initarg :source-form)))


(defun make-material (id shader source-form core-state)
  (make-instance 'material :id id :shader shader :source-form source-form
                           :core-state core-state))

(defun bind-material-uniforms (mat)
  (when mat
    (maphash
     (lambda (uniform-name material-value)
       (funcall (binder material-value)
                uniform-name
                (computed-value material-value)))
     (uniforms mat))))

(defun bind-material-buffers (mat)
  nil)

(defun bind-material (mat)
  (bind-material-uniforms mat)
  (bind-material-buffers mat))

;; Todo, these modify the semantic-buffer which then gets processed into a
;; new computed buffer.
(defun mat-ref (mat var)
  nil)

;; This is read only, it is the computed value in the material.
(defun mat-computed-ref (mat var)
  nil)

;; We can only set the semantic-value, which gets automatically upgraded to
;; the computed-value.
(defun (setf mat-ref) (new-val mat var)
  nil)





(defun parse-material (shader name body)
  "Return a function which creates a partially complete material instance.
It is partially complete because it does not yet have the shader binder
function available for it so BIND-UNIFORMS cannot yet be called on it."
  (let ((uniforms (cdar (member 'uniforms body
                                :key #'first :test #'eql/package-relaxed)))
        (blocks (cdar (member 'blocks body
                              :key #'first :test #'eql/package-relaxed))))
    `(lambda (core-state)
       (let ((mat (make-material ,name ,shader ',body core-state)))

         (setf
          ,@(loop :for (var val) :in uniforms :appending
                  `((gethash ,var (uniforms mat))
                    ;; we don't know the binder function we need yet...  because
                    ;; we don't yet know the official type of this uniform as
                    ;; defined by the shader program. We can only compute that
                    ;; after all shader programs are built.
                    (make-material-value :semantic-value ,val))))

         (setf
          ,@(loop :for (var val) :in blocks :appending
                  `((gethash ,var (blocks mat))
                    ;; we don't know the binder function we need yet...  because
                    ;; we don't yet know the official type of this uniform as
                    ;; defined by the shader program. We can only compute that
                    ;; after all shader programs are built.
                    (make-material-value :semantic-value ,val))))

         mat))))

(defun determine-binder-function (material glsl-type)
  (cond
    ((symbolp glsl-type)
     (ecase glsl-type
       (:sampler-2d (let ((unit (active-texture-unit material)))
                      (incf (active-texture-unit material))
                      (lambda (uniform-name texture-id)
                        (gl:active-texture unit)
                        (gl:bind-texture :texture-2d texture-id)
                        (shadow:uniform-int uniform-name unit))))
       (:bool #'shadow:uniform-int)
       (:int #'shadow:uniform-int)
       (:float #'shadow:uniform-float)
       (:vec2 #'shadow:uniform-vec2)
       (:vec3 #'shadow:uniform-vec3)
       (:vec4 #'shadow:uniform-vec4)
       (:mat2 #'shadow:uniform-mat2)
       (:mat3 #'shadow:uniform-mat3)
       (:mat4 #'shadow:uniform-mat4)))
    ((consp glsl-type)
     (ecase (first glsl-type)
       (:sampler-2d (let ((unit (active-texture-unit material)))
                      (incf (active-texture-unit material))
                      (lambda (uniform-name texture-id)
                        (gl:active-texture unit)
                        (gl:bind-texture :texture-2d texture-id)
                        (shadow:uniform-int-array uniform-name unit))))
       (:bool #'shadow:uniform-int-array)
       (:int #'shadow:uniform-int-array)
       (:float #'shadow:uniform-float-array)
       (:vec2 #'shadow:uniform-vec2-array)
       (:vec3 #'shadow:uniform-vec3-array)
       (:vec4 #'shadow:uniform-vec4-array)
       (:mat2 #'shadow:uniform-mat2-array)
       (:mat3 #'shadow:uniform-mat3-array)
       (:mat4 #'shadow:uniform-mat4-array)))
    (t
     (error "Cannot determine binder function for glsl-type: ~S~%"
            glsl-type))))

(defun annotate-material (material shader-program core-state)
  (maphash
   (lambda (uniform-name material-value)
     (format t "Checking material: ~A, uniform: ~A~%"
             (id material) uniform-name)

     (multiple-value-bind (shader-uniform-type-info presentp)
         (gethash uniform-name (shadow::uniforms shader-program))

       ;; 1. figure out of the variable name/path is present in the shader
       ;; program. good if so, error if not.
       (unless presentp
         (error "Material ~S uses unknown uniform ~S in shader ~S~%"
                (id material) uniform-name (id shader-program)))

       (let ((uniform-type (aref shader-uniform-type-info 1)))
         ;; 2. Find the uniform in the shader-program and get its type-info. Use
         ;; that to set the binder function.
         (setf (binder material-value)
               (determine-binder-function material uniform-type))

         ;; 3. Convert certain types like :sampler-2d away from the file
         ;; path and to a real texture-id. Poke through the core-state
         ;; to set up the textures/etc into the cache in core-state.
         (case uniform-type
           (:sampler-2d
            (cond
              ((and (stringp (semantic-value material-value))
                    (not (zerop (length (semantic-value material-value)))))

               (setf (computed-value material-value)
                     (rcache-lookup :texture core-state
                                    (semantic-value material-value)))

               (format t "annotate-material: material ~A uniform ~A :sampler-2d ~A -> texutre-id: ~A~%"
                       (id material) uniform-name
                       (semantic-value material-value)
                       (computed-value material-value)))
              (t
               (error "material ~A has a badly formed :sampler-2d value: ~A"
                      (id material) (semantic-value material-value)))))
           (otherwise
            ;; copy it over as identity.
            (setf (computed-value material-value)
                  (let ((thing (semantic-value material-value)))
                    (if (or (stringp thing)
                            (arrayp thing)
                            (listp thing)
                            (vectorp thing))
                        (copy-seq thing)
                        thing))))))))

   (uniforms material))

  ;; TODO: Do something with blocks, if required.


  )

;; TODO: After the partial materials and shaders have been loaded, we need to
;; resolve the materials to something we can actually bind to a real shader.
(defun resolve-all-materials (core-state)
  (format t "Attempting to resolve materials...~%")

  (maphash
   (lambda (material-name material-instance)
     (format t "Resolving material: ~A~%" material-name)
     (multiple-value-bind (shader-program present-p)
         (gethash (shader material-instance) (shaders core-state))

       ;; TODO: Add in when it actually works.
       #++(unless presentp
            (error "Material ~S uses an undefined shader: ~S~%"
                   (id material-instance)
                   (shader material-instance)))

       (annotate-material material-instance shader-program core-state)

       ))
   (materials core-state)))



(defmethod extension-file-type ((extension-type (eql 'materials)))
  "materials")

(defmethod prepare-extension ((extension-type (eql 'materials)) owner path)
  (let ((%temp-materials (make-hash-table)))
    (declare (special %temp-materials))
    (flet ((%prepare ()
             (load-extensions extension-type path)
             %temp-materials))
      (maphash
       (lambda (material-name gen-material-func)

         (format t "prepare-extension(materials): processing ~A~%"
                 material-name)

         (setf (gethash material-name (materials owner))
               ;; Create the partially resolved material.... we will fully
               ;; resolve it later by type checking the uniforms specified
               ;; and creating the binder annotations for the values.
               (funcall gen-material-func owner))

         )

       (%prepare)))))

(defmacro define-material (name (&body options) &body body)
  `(let* ((material-func ,(parse-material (second (member :shader options))
                                          `',name
                                          body)))
     (declare (special %temp-materials))
     ,(when (second (member :enabled options))
        `(setf (gethash ',name %temp-materials) material-func))))
