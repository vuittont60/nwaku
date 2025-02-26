## Waku Filter client for subscribing and receiving filtered messages

when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/options,
  chronicles,
  chronos,
  libp2p/protocols/protocol,
  bearssl/rand
import
  ../node/peer_manager,
  ../waku_core,
  ./common,
  ./protocol_metrics,
  ./rpc_codec,
  ./rpc

logScope:
  topics = "waku filter client"

type
  WakuFilterClient* = ref object of LPProtocol
    rng: ref HmacDrbgContext
    peerManager: PeerManager
    pushHandlers: seq[FilterPushHandler]

func generateRequestId(rng: ref HmacDrbgContext): string =
  var bytes: array[10, byte]
  hmacDrbgGenerate(rng[], bytes)
  return toHex(bytes)

proc sendSubscribeRequest(wfc: WakuFilterClient, servicePeer: RemotePeerInfo,
                          filterSubscribeRequest: FilterSubscribeRequest):
                        Future[FilterSubscribeResult]
                        {.async.} =
  trace "Sending filter subscribe request", peerId=servicePeer.peerId, filterSubscribeRequest

  let connOpt = await wfc.peerManager.dialPeer(servicePeer, WakuFilterSubscribeCodec)
  if connOpt.isNone():
    trace "Failed to dial filter service peer", servicePeer
    waku_filter_errors.inc(labelValues = [dialFailure])
    return err(FilterSubscribeError.peerDialFailure($servicePeer))

  let connection = connOpt.get()

  # TODO: this can raise an exception
  await connection.writeLP(filterSubscribeRequest.encode().buffer)

  let respBuf = await connection.readLp(MaxSubscribeResponseSize)
  let respDecodeRes = FilterSubscribeResponse.decode(respBuf)
  if respDecodeRes.isErr():
    trace "Failed to decode filter subscribe response", servicePeer
    waku_filter_errors.inc(labelValues = [decodeRpcFailure])
    return err(FilterSubscribeError.badResponse(decodeRpcFailure))

  let response = respDecodeRes.get()

  if response.requestId != filterSubscribeRequest.requestId:
    trace "Filter subscribe response requestId mismatch", servicePeer, response
    waku_filter_errors.inc(labelValues = [requestIdMismatch])
    return err(FilterSubscribeError.badResponse(requestIdMismatch))

  if response.statusCode != 200:
    trace "Filter subscribe error response", servicePeer, response
    waku_filter_errors.inc(labelValues = [errorResponse])
    let cause = if response.statusDesc.isSome(): response.statusDesc.get()
                else: "filter subscribe error"
    return err(FilterSubscribeError.parse(response.statusCode, cause=cause))

  return ok()

proc ping*(wfc: WakuFilterClient, servicePeer: RemotePeerInfo): Future[FilterSubscribeResult] {.async.} =
  let requestId = generateRequestId(wfc.rng)
  let filterSubscribeRequest = FilterSubscribeRequest.ping(requestId)

  return await wfc.sendSubscribeRequest(servicePeer, filterSubscribeRequest)

proc subscribe*(wfc: WakuFilterClient,
                servicePeer: RemotePeerInfo,
                pubsubTopic: PubsubTopic,
                contentTopics: seq[ContentTopic]):
              Future[FilterSubscribeResult]
              {.async.} =

  let requestId = generateRequestId(wfc.rng)
  let filterSubscribeRequest = FilterSubscribeRequest.subscribe(
    requestId = requestId,
    pubsubTopic = pubsubTopic,
    contentTopics = contentTopics
  )

  return await wfc.sendSubscribeRequest(servicePeer, filterSubscribeRequest)

proc unsubscribe*(wfc: WakuFilterClient,
                  servicePeer: RemotePeerInfo,
                  pubsubTopic: PubsubTopic,
                  contentTopics: seq[ContentTopic]):
                Future[FilterSubscribeResult]
                {.async.} =

  let requestId = generateRequestId(wfc.rng)
  let filterSubscribeRequest = FilterSubscribeRequest.unsubscribe(
    requestId = requestId,
    pubsubTopic = pubsubTopic,
    contentTopics = contentTopics
  )

  return await wfc.sendSubscribeRequest(servicePeer, filterSubscribeRequest)

proc unsubscribeAll*(wfc: WakuFilterClient, servicePeer: RemotePeerInfo):
                Future[FilterSubscribeResult]
                {.async.} =

  let requestId = generateRequestId(wfc.rng)
  let filterSubscribeRequest = FilterSubscribeRequest.unsubscribeAll(
    requestId = requestId
  )

  return await wfc.sendSubscribeRequest(servicePeer, filterSubscribeRequest)

proc registerPushHandler*(wfc: WakuFilterClient, handler: FilterPushHandler) =
  wfc.pushHandlers.add(handler)

proc initProtocolHandler(wfc: WakuFilterClient) =

  proc handler(conn: Connection, proto: string) {.async.} =
    let buf = await conn.readLp(int(MaxPushSize))

    let decodeRes = MessagePush.decode(buf)
    if decodeRes.isErr():
      error "Failed to decode message push", peerId=conn.peerId
      waku_filter_errors.inc(labelValues = [decodeRpcFailure])
      return

    let messagePush = decodeRes.value #TODO: toAPI() split here
    trace "Received message push", peerId=conn.peerId, messagePush

    for handler in wfc.pushHandlers:
      asyncSpawn handler(messagePush.pubsubTopic,
                         messagePush.wakuMessage)

    # Protocol specifies no response for now
    return

  wfc.handler = handler
  wfc.codec = WakuFilterPushCodec

proc new*(T: type WakuFilterClient,
          peerManager: PeerManager,
          rng: ref HmacDrbgContext
          ): T =

  let wfc = WakuFilterClient(
    rng: rng,
    peerManager: peerManager,
    pushHandlers: @[]
  )
  wfc.initProtocolHandler()
  wfc
