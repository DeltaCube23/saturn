(*
  structure node t value: data type, next: pointer to node t
  structure queue t Head: pointer to node t, Tail: pointer to node t, H lock: lock type, T lock: lock type
*)

type 'a node = Nil | Next of 'a * 'a node ref

type 'a t = {
  mutable head : 'a node ref;
  head_lock : Mutex.t;
  not_empty : Condition.t;
  not_full : Condition.t;
  size : int Atomic.t;
  capacity : int;
  mutable tail : 'a node ref;
  tail_lock : Mutex.t;
}

(* create and initialize the 2 lock queue *)
let create ?(max_size = 1_000_000) () =
  let dummy = ref Nil in
  {
    head = dummy;
    head_lock = Mutex.create ();
    not_empty = Condition.create ();
    not_full = Condition.create ();
    size = Atomic.make 0;
    capacity = max_size;
    tail = dummy;
    tail_lock = Mutex.create ();
  }

(* push element to tail of queue *)
let push t value =
  let new_tail = ref Nil in
  let new_node = Next (value, new_tail) in
  Mutex.lock t.tail_lock;
  (* Ensures queue is not full *)
  while Atomic.get t.size = t.capacity do
    Condition.wait t.not_full t.tail_lock
  done;
  (* Check if queue is empty before this insertion *)
  t.tail := new_node;
  t.tail <- new_tail;
  let empty = Atomic.fetch_and_add t.size 1 in
  Mutex.unlock t.tail_lock;
  (* If it was empty then signal the waiting pop threads to wake up *)
  if empty = 0 then (
    Mutex.lock t.head_lock;
    Mutex.unlock t.head_lock;
    Condition.broadcast t.not_empty)

(* pop element from head of queue *)
let pop t =
  Mutex.lock t.head_lock;
  (* Ensures queue is not empty *)
  while Atomic.get t.size = 0 do
    Condition.wait t.not_empty t.head_lock
  done;
  (* Check if queue is full before this deletion *)
  let popped =
    match !(t.head) with
    | Nil -> assert false
    | Next (value, next) ->
        t.head <- next;
        value
  in
  let full = Atomic.fetch_and_add t.size (-1) in
  Mutex.unlock t.head_lock;
  (* It it was full then signal the waiting push threads to wake up *)
  if full = t.capacity then (
    Mutex.lock t.tail_lock;
    Mutex.unlock t.tail_lock;
    Condition.broadcast t.not_full);
  popped

(* check if q is empty if the node head is pointing to is Nil *)
let is_empty t =
  Mutex.lock t.head_lock;
  let empty = !(t.head) in
  Mutex.unlock t.head_lock;
  empty = Nil

(* return element at head of queue *)
let peek t =
  Mutex.lock t.head_lock;
  let top = !(t.head) in
  Mutex.unlock t.head_lock;
  match top with Nil -> None | Next (value, _) -> Some value

(* push with no blocking condition, for stm tests *)
let unbounded_push t value =
  let new_tail = ref Nil in
  let new_node = Next (value, new_tail) in
  Mutex.lock t.tail_lock;
  t.tail := new_node;
  t.tail <- new_tail;
  Mutex.unlock t.tail_lock

(* pop with no blocking condition, for stm tests *)
let unbounded_pop t =
  Mutex.lock t.head_lock;
  let popped =
    match !(t.head) with
    | Nil -> None
    | Next (value, next) ->
        t.head <- next;
        Some value
  in
  Mutex.unlock t.head_lock;
  popped
