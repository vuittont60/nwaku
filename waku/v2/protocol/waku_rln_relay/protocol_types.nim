when (NimMajor, NimMinor) < (1, 4):
  {.push raises: [Defect].}
else:
  {.push raises: [].}

import
  std/[options, tables, deques],
  stew/arrayops,
  chronos, 
  web3,
  eth/keys
import
  ../waku_keystore,
  ../../../common/protobuf

type RlnRelayResult*[T] = Result[T, string]

## RLN is a Nim wrapper for the data types used in zerokit RLN
type RLN* {.incompleteStruct.} = object
type RLNResult* = RlnRelayResult[ptr RLN]

type
  MerkleNode* = array[32, byte] # Each node of the Merkle tee is a Poseidon hash which is a 32 byte value
  Nullifier* = array[32, byte]
  Epoch* = array[32, byte]
  RlnIdentifier* = array[32, byte]
  ZKSNARK* = array[128, byte]

# Custom data types defined for waku rln relay -------------------------
type RateLimitProof* = object
  ## RateLimitProof holds the public inputs to rln circuit as
  ## defined in https://hackmd.io/tMTLMYmTR5eynw2lwK9n1w?view#Public-Inputs
  ## the `proof` field carries the actual zkSNARK proof
  proof*: ZKSNARK
  ## the root of Merkle tree used for the generation of the `proof`
  merkleRoot*: MerkleNode
  ## the epoch used for the generation of the `proof`
  epoch*: Epoch
  ## shareX and shareY are shares of user's identity key
  ## these shares are created using Shamir secret sharing scheme
  ## see details in https://hackmd.io/tMTLMYmTR5eynw2lwK9n1w?view#Linear-Equation-amp-SSS
  shareX*: MerkleNode
  shareY*: MerkleNode
  ## nullifier enables linking two messages published during the same epoch
  ## see details in https://hackmd.io/tMTLMYmTR5eynw2lwK9n1w?view#Nullifiers
  nullifier*: Nullifier
  ## Application specific RLN Identifier
  rlnIdentifier*: RlnIdentifier

type ProofMetadata* = object
  nullifier*: Nullifier
  shareX*: MerkleNode
  shareY*: MerkleNode

type WakuRLNRelay* = ref object
  identityCredential*: IdentityCredential
  # membershipIndex denotes the index of a leaf in the Merkle tree
  # that contains the pk of the current peer
  # this index is used to retrieve the peer's authentication path
  membershipIndex*: MembershipIndex
  membershipContractAddress*: Address
  ethClientAddress*: string
  ethAccountAddress*: Option[Address]
  # this field is required for signing transactions
  # TODO may need to erase this ethAccountPrivateKey when is not used
  # TODO may need to make ethAccountPrivateKey mandatory
  ethAccountPrivateKey*: Option[PrivateKey]
  rlnInstance*: ptr RLN
  pubsubTopic*: string # the pubsub topic for which rln relay is mounted
                       # contentTopic should be of type waku_message.ContentTopic, however, due to recursive module dependency, the underlying type of ContentTopic is used instead
                       # TODO a long-term solution is to place types with recursive dependency inside one file
  contentTopic*: string
  # the log of nullifiers and Shamir shares of the past messages grouped per epoch
  nullifierLog*: Table[Epoch, seq[ProofMetadata]]
  lastEpoch*: Epoch # the epoch of the last published rln message
  validMerkleRoots*: Deque[MerkleNode] # An array of valid merkle roots, which are updated in a FIFO fashion
  lastSeenMembershipIndex*: MembershipIndex # the last seen membership index
  lastProcessedBlock*: BlockNumber # the last processed block number

type 
  MessageValidationResult* {.pure.} = enum
    Valid, 
    Invalid, 
    Spam
  MerkleNodeResult* = RlnRelayResult[MerkleNode]
  RateLimitProofResult* = RlnRelayResult[RateLimitProof]
  
# Protobufs enc and init
proc init*(T: type RateLimitProof, buffer: seq[byte]): ProtoResult[T] =
  var nsp: RateLimitProof
  let pb = initProtoBuffer(buffer)

  var proof: seq[byte]
  discard ? pb.getField(1, proof)
  discard nsp.proof.copyFrom(proof)

  var merkleRoot: seq[byte]
  discard ? pb.getField(2, merkleRoot)
  discard nsp.merkleRoot.copyFrom(merkleRoot)

  var epoch: seq[byte]
  discard ? pb.getField(3, epoch)
  discard nsp.epoch.copyFrom(epoch)

  var shareX: seq[byte]
  discard ? pb.getField(4, shareX)
  discard nsp.shareX.copyFrom(shareX)

  var shareY: seq[byte]
  discard ? pb.getField(5, shareY)
  discard nsp.shareY.copyFrom(shareY)

  var nullifier: seq[byte]
  discard ? pb.getField(6, nullifier)
  discard nsp.nullifier.copyFrom(nullifier)
  
  var rlnIdentifier: seq[byte]
  discard ? pb.getField(7, rlnIdentifier)
  discard nsp.rlnIdentifier.copyFrom(rlnIdentifier)

  return ok(nsp)

proc encode*(nsp: RateLimitProof): ProtoBuffer =
  var output = initProtoBuffer()

  output.write3(1, nsp.proof)
  output.write3(2, nsp.merkleRoot)
  output.write3(3, nsp.epoch)
  output.write3(4, nsp.shareX)
  output.write3(5, nsp.shareY)
  output.write3(6, nsp.nullifier)
  output.write3(7, nsp.rlnIdentifier)

  output.finish3()

  return output