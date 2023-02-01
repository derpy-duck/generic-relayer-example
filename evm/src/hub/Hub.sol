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
contract Hub is IWormholeReceiver {
    using BytesLib for bytes;

    address owner;
    IWormhole wormhole;
    ICoreRelayer coreRelayer;

    // Registered Spoke Contracts    
    mapping(uint16 => bytes32) registeredSpokeAddresses;
    uint16[] registeredSpokeChainIds;

    // Replay protection
    mapping(bytes32 => bool) completedWormholeMessages;

    // Chat Messages List
    struct ChatMessage {
        address sender;
        bytes message;
    }

    ChatMessage[] chatMessages;
    uint256 nextToDelete = 0;

    constructor(address wormhole_, address coreRelayer_) {
        wormhole = IWormhole(wormhole_); 
        coreRelayer = ICoreRelayer(coreRelayer_);
        owner = msg.sender;
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

        if(chatMessages.length > 32) {
            delete chatMessages[nextToDelete];
            nextToDelete += 1;
        }

        ICoreRelayer.DeliveryRequest[] memory requests = new ICoreRelayer.DeliveryRequest[](registeredSpokeChainIds.length);

        wormhole.publishMessage(1, encodeChatMessages(chatMessages), 200);

        for(uint256 i=0; i<registeredSpokeChainIds.length; i++) {
            uint16 chainId = registeredSpokeChainIds[i];
            requests[i] = ICoreRelayer.DeliveryRequest({
                targetChain: chainId,
                targetAddress: registeredSpokeAddresses[chainId],
                refundAddress: chainId == wormholeMessage.emitterChainId ? coreRelayer.toWormholeFormat(parsedMessage.sender) : registeredSpokeAddresses[chainId],
                computeBudget: coreRelayer.quoteGasDeliveryFee(chainId, 500000, coreRelayer.getDefaultRelayProvider()),
                applicationBudget: 0,
                relayParameters: coreRelayer.getDefaultRelayParams()
            });
        }
 
        ICoreRelayer.DeliveryRequestsContainer memory deliveryRequestsForSpokes = ICoreRelayer.DeliveryRequestsContainer({
            payloadId: 1,
            relayProviderAddress: address(coreRelayer.getDefaultRelayProvider()),
            requests: requests
        });

        coreRelayer.requestMultiforward(deliveryRequestsForSpokes, wormholeMessage.emitterChainId, 1);
        
    }

    function decodeChatMessage(bytes memory payload) public view returns(ChatMessage memory decodedMsg) {
        decodedMsg.sender = payload.toAddress(0);
        uint16 length = payload.toUint16(20);
        decodedMsg.message = payload.slice(22, length);
    }

    function encodeChatMessages(ChatMessage[] memory _chatMessages) public pure returns (bytes memory encodedMsg) {
        encodedMsg = abi.encodePacked(uint16(_chatMessages.length));
        for(uint16 i=0; i<_chatMessages.length; i++) {
            encodedMsg = abi.encodePacked(encodedMsg, _chatMessages[i].sender, uint16(_chatMessages[i].message.length), _chatMessages[i].message);
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
    function registerEmitter(
        uint16 emitterChainId,
        bytes32 emitterAddress
    ) public onlyOwner {
        if(registeredSpokeAddresses[emitterChainId] == bytes32(0x0)) {
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
