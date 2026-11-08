import std/[locks, os, monotimes]
import nuigi/util/pointer_queue
include nuigi/util/compat2

when defined(nimony):
  import std/rawthreads
  type WorkerThread = RawThread
else:
  type WorkerThread = Thread[pointer]

const
  Capacity = pointerQueueCapacity
  ProducerCount = 4
  MessagesPerProducer = 2000

type
  Message = object
    producer, sequence, checksum: int
  Queue = object
    lock: Lock
    startCondition: Cond
    payloads: PointerQueue
    ready, finished, rejected: int
    started, closed: bool
  Producer = object
    queue: ptr Queue
    messages: array[MessagesPerProducer, Message]

proc require(condition: bool, message: string) =
  if not condition:
    quit("thread queue test failed: " & message, 1)

proc initialize(queue: var Queue) =
  queue = default(Queue)
  queue.payloads.initPointerQueue()
  initLock(queue.lock)
  initCond(queue.startCondition)

proc close(queue: ptr Queue) =
  withLock queue.lock:
    queue.closed = true
    queue.payloads.close()
    broadcast(queue.startCondition)

proc tryPush(queue: ptr Queue, message: ptr Message): PointerQueueResult =
  queue.payloads.tryPush(message)

proc tryPop(queue: ptr Queue): ptr Message =
  cast[ptr Message](queue.payloads.pop())

proc producerMain(data: pointer) {.nimcall, gcsafe.} =
  let producer = cast[ptr Producer](data)
  let queue = producer.queue
  withLock queue.lock:
    inc queue.ready
    while not queue.started:
      wait(queue.startCondition, queue.lock)
  for index in 0 ..< MessagesPerProducer:
    producer.messages[index].checksum =
      producer.messages[index].producer * MessagesPerProducer + index
    # Ownership of this stable, unmanaged payload transfers on Accepted.
    var accepted = false
    while not accepted:
      case queue.tryPush(addr producer.messages[index])
      of QueueAccepted: accepted = true
      of QueueFull: sleep(1)
      of QueueClosed: quit("queue closed before producer finished", 1)
  withLock queue.lock:
    inc queue.finished
    while not queue.closed:
      wait(queue.startCondition, queue.lock)
  if queue.tryPush(addr producer.messages[0]) != QueueClosed:
    quit("producer enqueue accepted after close", 1)
  withLock queue.lock:
    inc queue.rejected

proc start(thread: var WorkerThread, producer: ptr Producer) =
  when defined(nimony):
    onRaiseQuit(thread.create(producerMain, producer))
  else:
    createThread(thread, producerMain, producer)

proc joinWorker(thread: var WorkerThread) =
  when defined(nimony):
    rawthreads.join(thread)
  else:
    joinThread(thread)

proc testCapacityAndClose() =
  var queue = default(Queue)
  queue.initialize()
  let q = addr queue
  var messages = default(array[Capacity + 1, Message])
  require(q.tryPop() == nil, "empty queue")
  for index in 0 ..< Capacity:
    require(q.tryPush(addr messages[index]) == QueueAccepted, "fill to capacity")
  require(q.tryPush(addr messages[Capacity]) == QueueFull, "explicit overflow")
  require(q.tryPop() == addr messages[0], "FIFO head")
  require(q.tryPush(addr messages[Capacity]) == QueueAccepted, "ring wraparound")
  q.close()
  q.close()
  require(q.tryPush(addr messages[0]) == QueueClosed, "reject after close")
  let batch = queue.payloads.drain()
  require(batch.count == Capacity, "drain detaches entire batch")
  for index in 1 .. Capacity:
    require(batch.items[index - 1] == addr messages[index], "drain closed queue in FIFO order")
  require(q.tryPop() == nil, "closed queue drained")
  deinitCond(queue.startCondition)
  deinitLock(queue.lock)
  queue.payloads.deinitPointerQueue()

proc testConcurrentProducers() =
  var queue = default(Queue)
  queue.initialize()
  let q = addr queue
  var producers = default(array[ProducerCount, Producer])
  var threads = default(array[ProducerCount, WorkerThread])
  for producerIndex in 0 ..< ProducerCount:
    producers[producerIndex].queue = addr queue
    for sequence in 0 ..< MessagesPerProducer:
      producers[producerIndex].messages[sequence] = Message(
        producer: producerIndex, sequence: sequence,
        checksum: -1)
    start(threads[producerIndex], addr producers[producerIndex])

  let deadline = getMonoTime().ticks + 30_000_000_000'i64
  while true:
    var ready = 0
    withLock queue.lock:
      ready = queue.ready
    if ready == ProducerCount:
      break
    require(getMonoTime().ticks < deadline, "producer startup timeout")
    sleep(1)
  withLock queue.lock:
    queue.started = true
    broadcast(queue.startCondition)

  var nextSequence = default(array[ProducerCount, int])
  var received = 0
  while true:
    let message = q.tryPop()
    if message != nil:
      require(message.producer >= 0 and message.producer < ProducerCount, "producer ID")
      require(message.sequence >= 0 and message.sequence < MessagesPerProducer, "sequence range")
      require(message.sequence == nextSequence[message.producer],
        "per-producer FIFO, no duplicates or missing messages")
      require(message == addr producers[message.producer].messages[message.sequence],
        "payload pointer identity")
      require(message.checksum == message.producer * MessagesPerProducer + message.sequence,
        "payload visibility")
      inc nextSequence[message.producer]
      inc received
    else:
      var finished = 0
      var pending = false
      withLock queue.lock:
        finished = queue.finished
        pending = queue.payloads.pending()
      if finished == ProducerCount and not pending:
        break
      sleep(1)
    require(getMonoTime().ticks < deadline, "concurrent queue timeout")

  q.close()
  for index in 0 ..< ProducerCount:
    joinWorker(threads[index])
    require(nextSequence[index] == MessagesPerProducer, "all producer messages consumed")
  require(received == ProducerCount * MessagesPerProducer, "exactly-once delivery")
  require(queue.rejected == ProducerCount, "all producers rejected after close")
  require(q.tryPop() == nil, "no leftover messages")
  deinitCond(queue.startCondition)
  deinitLock(queue.lock)
  queue.payloads.deinitPointerQueue()
  echo "thread queue: ", received, " messages, ", ProducerCount, " producers, FIFO/exactly-once OK"

testCapacityAndClose()
echo "thread queue: capacity/wraparound/close OK"
testConcurrentProducers()
