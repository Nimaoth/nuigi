## Bounded queue; producers never wait for free capacity. Ownership transfers on
## QueueAccepted; the consumer owns each pointer returned by pop.
import std/locks
include nuigi/util/compat2

const pointerQueueCapacity* = 256
type
  PointerQueueResult* = enum
    QueueAccepted, QueueFull, QueueClosed
  PointerQueue* = object
    lock: Lock
    slots: array[pointerQueueCapacity, pointer]
    head, count: int
    closed: bool
  PointerQueueBatch* = object
    count*: int
    items*: array[pointerQueueCapacity, pointer]

proc initPointerQueue*(queue: var PointerQueue) =
  queue = default(PointerQueue)
  initLock(queue.lock)

proc tryPush*(queue: var PointerQueue, payload: pointer): PointerQueueResult {.gcsafe, raises: [].} =
  withLock queue.lock:
    if queue.closed:
      return QueueClosed
    if queue.count == pointerQueueCapacity:
      return QueueFull
    queue.slots[(queue.head + queue.count) mod pointerQueueCapacity] = payload
    inc queue.count
    return QueueAccepted

proc pop*(queue: var PointerQueue): pointer {.gcsafe, raises: [].} =
  result = nil
  withLock queue.lock:
    if queue.count > 0:
      result = queue.slots[queue.head]
      queue.slots[queue.head] = nil
      queue.head = (queue.head + 1) mod pointerQueueCapacity
      dec queue.count

proc pending*(queue: var PointerQueue): bool {.gcsafe, raises: [].} =
  withLock queue.lock:
    return queue.count > 0

proc drain*(queue: var PointerQueue): PointerQueueBatch {.gcsafe, raises: [].} =
  result = default(PointerQueueBatch)
  withLock queue.lock:
    result.count = queue.count
    for i in 0 ..< queue.count:
      let slot = (queue.head + i) mod pointerQueueCapacity
      result.items[i] = queue.slots[slot]
      queue.slots[slot] = nil
    queue.head = 0
    queue.count = 0

proc close*(queue: var PointerQueue) {.gcsafe, raises: [].} =
  withLock queue.lock:
    queue.closed = true

proc deinitPointerQueue*(queue: var PointerQueue) =
  ## All producers must have joined; caller must first drain owned payloads.
  deinitLock(queue.lock)
