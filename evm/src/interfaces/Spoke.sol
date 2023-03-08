// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {IWormholeRelayer} from "../interfaces/IWormholeRelayer.sol";
import {IRelayProvider} from "../interfaces/IRelayProvider.sol";
import {IWormholeReceiver} from "../interfaces/IWormholeReceiver.sol";
import "../libraries/BytesLib.sol";

/**
 * @title A Cross-Chain Chat Application with Wormhole's Generic Relayers
 * @notice This contract uses Wormhole's generic-messaging and generic relayers to send chat messages
 * to contracts on other blockchains
 */
contract Spoke is IWormholeReceiver {
    using BytesLib for bytes;

    IWormhole wormhole;
    IWormholeRelayer wormholeRelayer;

    // Hub Contract
    bytes32 hubContract;
    uint16 hubChainId;

    // Replay protection
    mapping(bytes32 => bool) completedWormholeMessages;

    // Chat Messages List
    struct ChatMessage {
        address sender;
        uint16 chainId;
        bytes message;
    }

    ChatMessage[32] chatMessages;
    uint16 length;

    constructor(address wormhole_, address wormholeRelayer_, bytes32 hubContract_, uint16 hubChainId_) {
        wormhole = IWormhole(wormhole_);
        wormholeRelayer = IWormholeRelayer(wormholeRelayer_);
        hubContract = hubContract_;
        hubChainId = hubChainId_;
        length = 0;
    }

    function receiveWormholeMessages(bytes[] memory vaas, bytes[] memory additionalData) external payable {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (IWormhole.VM memory wormholeMessage, bool valid, string memory reason) = wormhole.parseAndVerifyVM(vaas[0]);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by the Hub
        require(
            wormholeMessage.emitterChainId == hubChainId && wormholeMessage.emitterAddress == hubContract,
            "Message not from the Hub"
        );

        /**
         * Check to see if this message has been consumed already. If not,
         * save the parsed message in the receivedMessages mapping.
         *
         * This check can protect against replay attacks in xDapps where messages are
         * only meant to be consumed once.
         */
        require(!completedWormholeMessages[wormholeMessage.hash], "message already consumed");
        completedWormholeMessages[wormholeMessage.hash] = true;

        // set chatMessages to be the decoded payload
        decodeAndSetChatMessages(wormholeMessage.payload);
    }

    function getChatMessages() public view returns (ChatMessage[32] memory, uint16) {
        return (chatMessages, length);
    }

    function sendChatMessage(bytes memory message)
        public
        payable
        returns (uint64 msgWhSequence, uint64 coreRelayerWhSequence)
    {
        require(message.length <= type(uint16).max, "Message too large");
        msgWhSequence = wormhole.publishMessage(
            1, encodeChatMessage(ChatMessage({sender: msg.sender, chainId: wormhole.chainId(), message: message})), 200
        );
        coreRelayerWhSequence =
            wormholeRelayer.send{value: msg.value}(hubChainId, hubContract, hubContract, msg.value, 0, 1);
    }

    function decodeChatMessage(bytes memory payload, uint256 payloadIndex, uint16 chatMessageIndex) public {
        chatMessages[chatMessageIndex].sender = payload.toAddress(payloadIndex);
        chatMessages[chatMessageIndex].chainId = payload.toUint16(payloadIndex + 20);
        uint16 length_ = payload.toUint16(payloadIndex + 22);
        chatMessages[chatMessageIndex].message = payload.slice(payloadIndex + 24, length_);
    }

    function decodeAndSetChatMessages(bytes memory payload) public {
        length = payload.toUint16(0);
        require(length <= 32, "Message list too long");
        uint256 index = 2;
        for (uint16 i = 0; i < length; i++) {
            decodeChatMessage(payload, index, i);
            index += chatMessages[i].message.length + 24;
        }
    }

    function encodeChatMessage(ChatMessage memory _chatMessage) public pure returns (bytes memory encodedMsg) {
        encodedMsg = abi.encodePacked(
            _chatMessage.sender, _chatMessage.chainId, uint16(_chatMessage.message.length), _chatMessage.message
        );
    }
}
