// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import {IWormhole} from "../interfaces/IWormhole.sol";
import {ICoreRelayer} from "../interfaces/ICoreRelayer.sol";
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
    ICoreRelayer coreRelayer;

    // Hub Contract
    bytes32 hubContract;
    uint16 hubChainId;

    // Replay protection
    mapping(bytes32 => bool) completedWormholeMessages;

    // Chat Messages List
    struct ChatMessage {
        address sender;
        bytes message;
    }
    ChatMessage[32] chatMessages;
    uint16 length;

    constructor(address wormhole_, address coreRelayer_, bytes32 hubContract_, uint16 hubChainId_) {
        wormhole = IWormhole(wormhole_); 
        coreRelayer = ICoreRelayer(coreRelayer_);
        hubContract = hubContract_;
        hubChainId = hubChainId_;
        length = 0;
    }

    function receiveWormholeMessages(bytes[] memory vaas, bytes[] memory additionalData) external payable {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (
            IWormhole.VM memory wormholeMessage,
            bool valid,
            string memory reason
        ) = wormhole.parseAndVerifyVM(vaas[0]);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by the Hub
        require(wormholeMessage.emitterChainId == hubChainId && wormholeMessage.emitterAddress == hubContract, "Message not from the Hub");

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

    function sendChatMessage(bytes memory message) public payable {
        require(message.length <= type(uint16).max, "Message too large");
        wormhole.publishMessage(1, encodeChatMessage(ChatMessage({sender: msg.sender, message: message})), 200);
        coreRelayer.requestDelivery{value: msg.value}(ICoreRelayer.DeliveryRequest({
            targetChain: hubChainId,
            targetAddress: hubContract,
            refundAddress: hubContract,
            computeBudget: msg.value, 
            applicationBudget: 0,
            relayParameters: coreRelayer.getDefaultRelayParams()
        }), 1, coreRelayer.getDefaultRelayProvider());
    }

    function decodeChatMessage(bytes memory payload, uint256 payloadIndex, uint16 chatMessageIndex) public {
        chatMessages[chatMessageIndex].sender = payload.toAddress(payloadIndex);
        uint16 length_ = payload.toUint16(payloadIndex+20);
        chatMessages[chatMessageIndex].message = payload.slice(payloadIndex+22, length_);
    }

    function decodeAndSetChatMessages(bytes memory payload) public {
        length = payload.toUint16(0);
        require(length <= 32, "Message list too long");
        uint256 index = 2;
        for(uint16 i=0; i<length; i++) {
            decodeChatMessage(payload, index, i);
            index += chatMessages[i].message.length + 22;
        }
    }

    function encodeChatMessage(ChatMessage memory _chatMessage) public pure returns (bytes memory encodedMsg) {
        encodedMsg = abi.encodePacked(_chatMessage.sender, uint16(_chatMessage.message.length), _chatMessage.message);
    }
}
