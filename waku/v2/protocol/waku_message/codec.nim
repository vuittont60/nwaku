## Waku Message module: encoding and decoding
# See:
# - RFC 14: https://rfc.vac.dev/spec/14/
# - Proto definition: https://github.com/vacp2p/waku/blob/main/waku/message/v1/message.proto
when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}


import
  ../../../common/protobuf,
  ../../utils/time,
  ./message


proc encode*(message: WakuMessage): ProtoBuffer =
  var buf = initProtoBuffer()

  buf.write3(1, message.payload)
  buf.write3(2, message.contentTopic)
  buf.write3(3, message.version)
  buf.write3(10, zint64(message.timestamp))
  when defined(rln):
    buf.write3(21, message.proof)
  buf.write3(31, message.ephemeral)
  buf.finish3()

  buf

proc decode*(T: type WakuMessage, buffer: seq[byte]): ProtoResult[T] =
  var msg = WakuMessage(ephemeral: false)
  let pb = initProtoBuffer(buffer)

  var payload: seq[byte]
  if not ?pb.getField(1, payload):
    return err(ProtoError.RequiredFieldMissing)
  else:
    msg.payload = payload

  var topic: ContentTopic
  if not ?pb.getField(2, topic):
    return err(ProtoError.RequiredFieldMissing)
  else:
    msg.contentTopic = topic

  var version: uint32
  if not ?pb.getField(3, version):
    msg.version = 0
  else:
    msg.version = version

  var timestamp: zint64
  if not ?pb.getField(10, timestamp):
    msg.timestamp = Timestamp(0)
  else:
    msg.timestamp = Timestamp(timestamp)

  # Experimental: this is part of https://rfc.vac.dev/spec/17/ spec
  when defined(rln):
    var proof: seq[byte]
    if not ?pb.getField(21, proof):
      msg.proof = @[]
    else:
      msg.proof = proof

  var ephemeral: uint
  if not ?pb.getField(31, ephemeral):
    msg.ephemeral = false
  else:
    msg.ephemeral = bool(ephemeral)

  ok(msg)