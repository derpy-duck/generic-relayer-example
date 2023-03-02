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
contract Hub is IWormholeReceiver {
    using BytesLib for bytes;

    address owner;
    IWormhole wormhole;
    IWormholeRelayer wormholeRelayer;

    // Registered Spoke Contracts
    mapping(uint16 => bytes32) registeredSpokeAddresses;
    uint16[] registeredSpokeChainIds;

    // Replay protection
    mapping(bytes32 => bool) completedWormholeMessages;

    // Chat Messages List
    struct ChatMessage {
        address sender;
        uint16 chainId;
        bytes message;
    }

    ChatMessage[] chatMessages;
    uint256 nextToDelete = 0;

    constructor(address wormhole_, address wormholeRelayer_) {
        wormhole = IWormhole(wormhole_);
        wormholeRelayer = IWormholeRelayer(wormholeRelayer_);
        owner = msg.sender;
    }

    function receiveWormholeMessages(bytes[] memory vaas, bytes[] memory additionalData) external payable {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (IWormhole.VM memory wormholeMessage, bool valid, string memory reason) = wormhole.parseAndVerifyVM(vaas[0]);

        // confirm that the Wormhole core contract verified the message
        require(valid, reason);

        // verify that this message was emitted by a spoke
        require(verifyEmitter(wormholeMessage), "unknown emitter");

        /**
         * Check to see if this message has been consumed already. If not,
         * save the parsed message in the receivedMessages mapping.
         *
         * This check can protect against replay attacks in xDapps where messages are
         * only meant to be consumed once.
         */
        require(!completedWormholeMessages[wormholeMessage.hash], "message already consumed");
        completedWormholeMessages[wormholeMessage.hash] = true;

        // decode the message payload into the HelloWorldMessage struct
        ChatMessage memory parsedMessage = decodeChatMessage(wormholeMessage.payload);

        chatMessages.push(parsedMessage);

        if (chatMessages.length > 32) {
            delete chatMessages[nextToDelete];
            nextToDelete += 1;
        }

        IWormholeRelayer.Send[] memory requests = new IWormholeRelayer.Send[](registeredSpokeChainIds.length);

        // Publish a wormhole message containing all of the chat messages on the Hub
        wormhole.publishMessage(1, encodeChatMessages(chatMessages), 200);

        // Construct an array of 'Send' requests, to forward this message to all of the registered spokes
        uint256 counter = 0;
        for (uint256 i = 0; i < registeredSpokeChainIds.length; i++) {
            // Place the spoke that the latest message came from at the front, so that any leftover transaction fee is sent there
            if (i > 0 && (registeredSpokeChainIds[counter] == wormholeMessage.emitterChainId)) {
                counter += 1;
            }
            uint16 chainId = (i == 0 ? wormholeMessage.emitterChainId : registeredSpokeChainIds[counter]);

            // Construct a 'Send' request to go to the i-th registered chain (excluding the chain that the latest message came from, which is at index 0)
            requests[i] = IWormholeRelayer.Send({
                targetChain: chainId,
                targetAddress: registeredSpokeAddresses[chainId],
                refundAddress: chainId == wormholeMessage.emitterChainId
                    ? wormholeRelayer.toWormholeFormat(parsedMessage.sender)
                    : registeredSpokeAddresses[chainId],
                maxTransactionFee: wormholeRelayer.quoteGas(chainId, 500000, wormholeRelayer.getDefaultRelayProvider()),
                receiverValue: 0,
                relayParameters: wormholeRelayer.getDefaultRelayParams()
            });
        }

        IWormholeRelayer.MultichainSend memory sendToSpokes = IWormholeRelayer.MultichainSend({
            relayProviderAddress: address(wormholeRelayer.getDefaultRelayProvider()),
            requests: requests
        });

        wormholeRelayer.multichainForward(sendToSpokes, 1);
    }

    function decodeChatMessage(bytes memory payload) public pure returns (ChatMessage memory decodedMsg) {
        decodedMsg.sender = payload.toAddress(0);
        decodedMsg.chainId = payload.toUint16(20);
        uint16 length = payload.toUint16(22);
        decodedMsg.message = payload.slice(24, length);
    }

    function encodeChatMessages(ChatMessage[] memory _chatMessages) public pure returns (bytes memory encodedMsg) {
        encodedMsg = abi.encodePacked(uint16(_chatMessages.length));
        for (uint16 i = 0; i < _chatMessages.length; i++) {
            encodedMsg = abi.encodePacked(
                encodedMsg,
                _chatMessages[i].sender,
                _chatMessages[i].chainId,
                uint16(_chatMessages[i].message.length),
                _chatMessages[i].message
            );
        }
    }

    /**
     * @notice Registers foreign spokes (Spoke contracts) with this Hub
     * @dev Only the deployer (owner) can invoke this method
     * @param emitterChainId Wormhole chainId of the contract being registered
     * See https://book.wormhole.com/reference/contracts.html for more information.
     * @param emitterAddress 32-byte address of the contract being registered. For EVM
     * contracts the first 12 bytes should be zeros.
     */
    function registerEmitter(uint16 emitterChainId, bytes32 emitterAddress) public onlyOwner {
        if (registeredSpokeAddresses[emitterChainId] == bytes32(0x0)) {
            registeredSpokeChainIds.push(emitterChainId);
        }
        registeredSpokeAddresses[emitterChainId] = emitterAddress;
    }

    function verifyEmitter(IWormhole.VM memory vm) internal view returns (bool) {
        // Verify that the sender of the Wormhole message is a trusted
        // Spoke contract.
        return registeredSpokeAddresses[vm.emitterChainId] == vm.emitterAddress;
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "caller not the owner");
        _;
    }
}
