(in-package :gear)

(defclass flow-state ()
  ((%name :accessor name
          :initarg :name)
   (%policy :accessor policy
            :initarg :policy)
   (%exitingp :accessor exitingp
              :initarg :exitingp)
   (%selector :accessor selector
              :initarg :selector)
   (%action :accessor action
            :initarg :action)
   (%transition :accessor transition
                :initarg :transition)
   (%reset :accessor reset
           :initarg :reset)))

(defun make-flow-state (&rest initargs)
  (apply #'make-instance 'flow-state  initargs))

(defun canonicalize-binding (binding)
  (if (symbolp binding)
      (list binding nil)
      (list (first binding) (second binding))))

(defun binding-partition (bindings)
  (loop :for (b v) :in bindings
        :collect b :into bs
        :collect v :into vs
        :finally (return (values bs vs))))

(defun gen-reset-function (symbols values)
  (let* ((tmp-symbols
           (loop :for sym :in symbols
                 :collect (gensym (concatenate 'string (symbol-name sym)
                                               "-ONCE-ONLY-"))))
         (once-only-bindings (mapcar (lambda (tsym value) `(,tsym ,value))
                                     tmp-symbols
                                     values)))
    `(let ,once-only-bindings
       (lambda ()
         ,(when (plusp (length tmp-symbols))
            `(setf
              ,@(mapcan
                 (lambda (symbol value)
                   `(,symbol ,value))
                 symbols
                 tmp-symbols)))))))

(defun ensure-matched-symbol (symbol name)
  (assert (string= (symbol-name symbol) (string-upcase name))))

(defun parse-flow-state-functions (name funcs)
  "Parse the selection, action, and transition form from the FUNCS list.
They can be in any order, but return them as a values in the specific order
of selector, action, and transition."
  (let ((ht (make-hash-table :test #'eq)))

    (dolist (func-form funcs)
      (when func-form
        (setf (gethash (first func-form) ht)
              (second func-form))))

    (multiple-value-bind (selector sel-present-p)
        (gethash 'selector ht)
      (multiple-value-bind (action act-present-p)
          (gethash 'action ht)
        (multiple-value-bind (transition trans-present-p)
            (gethash 'transition ht)

          (unless sel-present-p
            (error "Missing selector function in flow-state: ~A" name))
          (unless act-present-p
            (error "Missing action functions in flow-state: ~A" name))
          (unless trans-present-p
            (error "Missing transition function in flow-state: ~A" name))

          ;; now return them in the canonical order.
          (values selector action transition))))))

(defun parse-flow-state (form)
  "Parse a single flow-state DSL form and return a form which creates the
flow-state CLOS instance for it."
  (destructuring-bind (match name policy binds . funcs) form
    (multiple-value-bind (selector action transition)
        (parse-flow-state-functions name funcs)
      (let ((binds (mapcar #'canonicalize-binding binds)))
        (multiple-value-bind (bind-syms bind-vals) (binding-partition binds)
          (ensure-matched-symbol match "flow-state")
          (let ((reset-function (gen-reset-function bind-syms bind-vals)))
            ;; Generate the instance maker for this flow-state.
            `(,name
              (let ,binds ; these are canonicalized, available for user.
                ;; TODO: Add a generated function to get the binding values out
                ;; in order of definition.
                (make-flow-state :name ',name
                                 :policy ,policy
                                 :exitingp ,(null transition)
                                 :selector ,selector
                                 :action ,action
                                 :transition ,transition
                                 :reset ,reset-function)))))))))

(defun get-flow-state-variables (flow-states)
  (loop :for (nil name . nil) :in flow-states
        :collect `(,name ',name) :into binds
        :collect `(declare (ignorable ,name)) :into ignores
        :finally (return (values binds ignores))))

(defun parse-flow (form)
  "Parse a single flow DSL node into a form that evaluates to a hash table
containing each flow-state indexed by name."
  (destructuring-bind (match flow-name . flow-states) form
    (multiple-value-bind (binds ignores) (get-flow-state-variables flow-states)
      (let ((flow-table (gensym)))
        (ensure-matched-symbol match "flow")
        `(,flow-name
          (let ((,flow-table (make-hash-table :test #'eq))
                ,@binds)
            ,@ignores
            ,@(loop :for (name state) :in (mapcar #'parse-flow-state flow-states)
                    :collect `(setf (gethash ',name ,flow-table) ,state))
            ,flow-table))))))

(defun parse-call-flows (form)
  "Parse an entire call-flow and return a list of the name of it and a form
which evaluates to a hash table of flows keyed by their name."
  (let ((call-flow-table (gensym)))
    `(let ((,call-flow-table (make-hash-table :test #'eq)))
       ,@(loop :for (name flow) :in (mapcar #'parse-flow form)
               :collect `(setf (gethash ',name ,call-flow-table) ,flow))
       ,call-flow-table)))

(defun execute-flow (core-state call-flow-name flow-name flow-state-name
                     &key come-from-state-name)
  "Find the CALL-FLOW-NAME call flow in the CORE-STATE, then lookup the flow
FLOW-NAME, and then the state FLOW-STATE-NAME inside of that flow. Start
execution of the flow from FLOW-STATE-NAME. Return a values of two states, the
one which executed before the currnet one which led to an exit of the call-flow.
COME-FROM-STATE-NAME is an arbitrary symbol that indicates the previous
flow-state name. This is often a symbolic name so execute-flow can determine how
the flow exited. Return two values The previous state name and the current state
name which resulted in the exiting of the flow."
  (slog:emit :flow.enter call-flow-name flow-name flow-state-name)
  (loop :with call-flow = (get-call-flow call-flow-name core-state)
        :with flow = (get-flow flow-name call-flow)
        :with flow-state = (get-flow-state flow-state-name flow)
        :with current-state-name = come-from-state-name
        :with last-state-name
        :with selections
        :do (slog:emit :flow.state.process
                       (name flow-state)
                       (exitingp flow-state))
            ;; Step 1: Record state transition and update to current.
            (setf last-state-name current-state-name
                  current-state-name (name flow-state))
            ;; Step 2: Perform execution policy
            (case (policy flow-state)
              (:reset                   ; Execute the resetting thunk
               (funcall (reset flow-state))))
            ;; Step 3: Run Selector Function
            (setf selections
                  (when (selector flow-state)
                    (slog:emit :flow.call.selector)
                    (funcall (selector flow-state) core-state)))
            ;; Step 4: Iterate the action across everything in the selections.
            ;; NOTE: This is not a map-tree or anything complex. It just assumes
            ;; selection is going to be one of:
            ;; a single hash table instance
            ;; a single instance of some class
            ;; a list of things that are either hash tables or class instances.
            (labels ((act-on-item (item)
                       (cond
                         ((hash-table-p item)
                          (when (action flow-state)
                            (slog:emit :flow.call.action.hash)
                            (maphash
                             (lambda (k v)
                               (declare (ignore k))
                               (funcall (action flow-state) core-state v))
                             item)))
                         ((atom item)
                          (when (action flow-state)
                            (slog:emit :flow.call.action.instance)
                            (funcall (action flow-state) core-state item))))))
              (if (consp selections)
                  (map nil #'act-on-item selections)
                  (act-on-item selections)))
            ;; Step 5: Exit if reached exiting state.
            (when (exitingp flow-state)
              (slog:emit :flow.exit call-flow-name flow-name current-state-name)
              (return-from execute-flow
                (values last-state-name current-state-name)))
            ;; Step 6: Run the transition function to determine the next
            ;; flow-state. Currently, a transition can only go into the SAME
            ;; flow.
            (slog:emit :flow.call.transition)
            (setf flow-state
                  (gethash (funcall (transition flow-state) core-state) flow))))

(defun get-call-flow (call-flow-name core-state)
  (gethash call-flow-name (call-flow-table core-state)))

(defun get-flow (flow-name call-flow)
  (gethash flow-name call-flow))

(defun get-flow-state (flow-state-name flow)
  (gethash flow-state-name flow))

(defmethod extension-file-type ((extension-type (eql 'call-flow)))
  "flow")

(defmacro call-flow-definition (name (&key enabled) &body body)
  `(let ()
     (declare (special %temp-call-flow))
     ,(when enabled
        `(setf (gethash ,name %temp-call-flow)
               ,(parse-call-flows body)))))
