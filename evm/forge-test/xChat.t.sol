// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/spoke/Spoke.sol";
import "../src/hub/Hub.sol";
import {WormholeSimulator} from "wormhole-solidity/WormholeSimulator.sol";
import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ICoreRelayer} from "../src/interfaces/ICoreRelayer.sol";
import {IRelayProvider} from "../src/interfaces/IRelayProvider.sol";

import "forge-std/console.sol";
import "../src/libraries/BytesLib.sol";

/**
 * @title A Test Suite for the EVM HelloWorld Contracts
 */
contract xChatTest is Test {

    using BytesLib for bytes;
    // guardian private key for simulated signing of Wormhole messages
    uint256 guardianSigner;

    // contract instances
    IWormhole wormhole;
    WormholeSimulator wormholeSimulator;
    ICoreRelayer coreRelayer; 
    IRelayProvider relayProvider;

    Hub hub;
    Spoke spoke;

    uint16 hubChainId;

    error InsufficientFunds(string reason);
    error MsgValueTooLow(); // msg.value must cover the budget specified
    error NonceIsZero();
    error NoDeliveryInProcess();
    error CantRequestMultipleForwards();
    error RelayProviderDoesNotSupportTargetChain();
    error RolloverChainNotIncluded(); // Rollover chain was not included in the forwarding request
    error ChainNotFoundInDeliveryRequests(uint16 chainId); // Required chain not found in the delivery requests
    error ReentrantCall();
    error InvalidEmitterInOriginalDeliveryVM(uint8 index);
    error InvalidRedeliveryVM(string reason);
    error InvalidEmitterInRedeliveryVM();
    error MismatchingRelayProvidersInRedelivery(); // The same relay provider must be specified when doing a single VAA redeliver
    error ProviderAddressIsNotSender(); // msg.sender must be the provider
    error RedeliveryRequestDoesNotTargetThisChain();
    error OriginalDeliveryRequestDidNotTargetThisChain();
    error InvalidVaa(uint8 index);
    error InvalidEmitter();
    error DeliveryRequestNotSufficientlyFunded(); // This delivery request was not sufficiently funded, and must request redelivery
    error UnexpectedRelayer(); // Specified relayer is not the relayer delivering the message
    error InsufficientRelayerFunds(); // The relayer didn't pass sufficient funds (msg.value does not cover the necessary budget fees)
    error AlreadyDelivered(); // The message was already delivered.
    error TargetChainIsNotThisChain(uint16 targetChainId);
    error SrcNativeCurrencyPriceIsZero();
    error DstNativeCurrencyPriceIsZero();

    /**
     * @notice Sets up the wormholeSimulator contracts and deploys HelloWorld
     * contracts before each test is executed.
     */
    function setUp() public {
        // verify that we're using the correct fork (AVAX mainnet in this case)
        require(block.chainid == vm.envUint("TESTING_FUJI_FORK_CHAINID"), "wrong evm");

        hubChainId = uint16(vm.envUint("TESTING_FUJI_WORMHOLE_CHAINID"));

        // this will be used to sign Wormhole messages
        guardianSigner = uint256(vm.envBytes32("TESTING_DEVNET_GUARDIAN"));

        // set up Wormhole using Wormhole existing on AVAX mainnet
        wormholeSimulator = new WormholeSimulator(vm.envAddress("TESTING_FUJI_WORMHOLE_ADDRESS"), guardianSigner);

        // we may need to interact with Wormhole throughout the test
        wormhole = wormholeSimulator.wormhole();

        // verify Wormhole state from fork
        require(wormhole.chainId() == uint16(vm.envUint("TESTING_FUJI_WORMHOLE_CHAINID")), "wrong chainId");
        require(wormhole.messageFee() == vm.envUint("TESTING_FUJI_WORMHOLE_MESSAGE_FEE"), "wrong messageFee");
        require(
            wormhole.getCurrentGuardianSetIndex() == uint32(vm.envUint("TESTING_FUJI_WORMHOLE_GUARDIAN_SET_INDEX")),
            "wrong guardian set index"
        );
        
        coreRelayer = ICoreRelayer(vm.envAddress("TESTING_FUJI_CORERELAYER_ADDRESS"));
        relayProvider = coreRelayer.getDefaultRelayProvider();

        hub = new Hub(address(wormhole), address(coreRelayer));
        spoke = new Spoke(address(wormhole), address(coreRelayer), coreRelayer.toWormholeFormat(address(hub)), hubChainId);
        hub.registerEmitter(hubChainId, coreRelayer.toWormholeFormat(address(spoke)));
    }

    function testFullFlow1Msg(Spoke.ChatMessage[32] memory msgs) public {
        vm.deal(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(hubChainId)), type(uint256).max);
        vm.recordLogs();
        for(uint16 i=0; i<2; i++) {
            vm.getRecordedLogs();
            vm.deal(msgs[i].sender, type(uint128).max);

            uint256 quote = coreRelayer.quoteGasDeliveryFee(hubChainId, 12000000*2, relayProvider);

            vm.prank(msgs[i].sender);
            spoke.sendChatMessage{value: quote}(msgs[i].message);
            genericRelayer(hubChainId, 2);
            genericRelayer(hubChainId, 2);
            (Spoke.ChatMessage[32] memory msgsReturned, uint16 length) = spoke.getChatMessages();
            require(length == i+1, "Wrong length");
            for(uint16 j=0; j<length; j++) {
                require(msgsReturned[j].sender == msgs[j].sender, "Wrong sender of a message");
                require(keccak256(msgsReturned[j].message) == keccak256(msgs[j].message), "Wrong message");
            }
            console.log("Balance Used: ");
            console.log((type(uint128).max - address(msgs[i].sender).balance));
        }

    }

    function testFullFlow32Msgs(Spoke.ChatMessage[32] memory msgs) public {
        vm.deal(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(hubChainId)), type(uint256).max);
        vm.recordLogs();
        for(uint16 i=0; i<32; i++) {
            vm.getRecordedLogs();
            vm.deal(msgs[i].sender, type(uint128).max);

            uint256 quote = coreRelayer.quoteGasDeliveryFee(hubChainId, 12000000*2, relayProvider);

            vm.prank(msgs[i].sender);
            spoke.sendChatMessage{value: quote}(msgs[i].message);
            genericRelayer(hubChainId, 2);
            genericRelayer(hubChainId, 2);
            (Spoke.ChatMessage[32] memory msgsReturned, uint16 length) = spoke.getChatMessages();
            require(length == i+1, "Wrong length");
            for(uint16 j=0; j<length; j++) {
                require(msgsReturned[j].sender == msgs[j].sender, "Wrong sender of a message");
                require(keccak256(msgsReturned[j].message) == keccak256(msgs[j].message), "Wrong message");
            }
            console.log("Balance Used: ");
            console.log((type(uint128).max - address(uint160(uint256(i))).balance));
        }

    }


    /**
     *
     *
     * GENERIC RELAYER CODE
     *
     *
     */

    mapping(uint256 => bool) nonceCompleted;

    mapping(bytes32 => ICoreRelayer.TargetDeliveryParametersSingle) pastDeliveries;

    function genericRelayer(uint16 chainId, uint8 num) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes[] memory encodedVMs = new bytes[](num);
        for (uint256 i = 0; i < num; i++) {
            encodedVMs[i] = wormholeSimulator.fetchSignedMessageFromLogs(
                entries[i], chainId, address(uint160(uint256(bytes32(entries[i].topics[1]))))
            );
        }

        IWormhole.VM[] memory parsed = new IWormhole.VM[](encodedVMs.length);
        for (uint16 i = 0; i < encodedVMs.length; i++) {
            parsed[i] = wormhole.parseVM(encodedVMs[i]);
        }

        for (uint16 i = 0; i < encodedVMs.length; i++) {
            if (!nonceCompleted[parsed[i].nonce]) {
                nonceCompleted[parsed[i].nonce] = true;
                uint8 length = 1;
                for (uint16 j = i + 1; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        length++;
                    }
                }
                bytes[] memory deliveryInstructions = new bytes[](length);
                uint8 counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        deliveryInstructions[counter] = encodedVMs[j];
                        counter++;
                    }
                }
                counter = 0;
                for (uint16 j = i; j < encodedVMs.length; j++) {
                    if (parsed[i].nonce == parsed[j].nonce) {
                        if (
                            parsed[j].emitterAddress == coreRelayer.toWormholeFormat(address(coreRelayer))
                                && (parsed[j].emitterChainId == chainId)
                        ) {
                            genericRelay(counter, encodedVMs[j], deliveryInstructions, parsed[j]);
                        }
                        counter += 1;
                    }
                }
            }
        }
        for (uint8 i = 0; i < encodedVMs.length; i++) {
            nonceCompleted[parsed[i].nonce] = false;
        }
    }

    function genericRelay(
        uint8 counter,
        bytes memory encodedVM,
        bytes[] memory deliveryInstructions,
        IWormhole.VM memory parsed
    ) internal {
        uint8 payloadId = parsed.payload.toUint8(0);
        if (payloadId == 1) {
            ICoreRelayer.DeliveryInstructionsContainer memory container =
                coreRelayer.getDeliveryInstructionsContainer(parsed.payload);
            for (uint8 k = 0; k < container.instructions.length; k++) {
                uint256 budget =
                    container.instructions[k].maximumRefundTarget + container.instructions[k].applicationBudgetTarget;
                uint16 targetChain = container.instructions[k].targetChain;
                ICoreRelayer.TargetDeliveryParametersSingle memory package = ICoreRelayer.TargetDeliveryParametersSingle({
                    encodedVMs: deliveryInstructions,
                    deliveryIndex: counter,
                    multisendIndex: k,
                    relayerRefundAddress: payable(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(targetChain)))
                });
                uint256 wormholeFee = wormhole.messageFee();
                vm.prank(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(targetChain)));
                coreRelayer.deliverSingle{value: (budget + wormholeFee)}(package);
                pastDeliveries[keccak256(abi.encodePacked(parsed.hash, k))] = package;
            }
        } else if (payloadId == 2) {
            ICoreRelayer.RedeliveryByTxHashInstruction memory instruction =
                coreRelayer.getRedeliveryByTxHashInstruction(parsed.payload);
            ICoreRelayer.TargetDeliveryParametersSingle memory originalDelivery =
                pastDeliveries[keccak256(abi.encodePacked(instruction.sourceTxHash, instruction.multisendIndex))];
            uint16 targetChain = instruction.targetChain;
            uint256 budget = instruction.newMaximumRefundTarget + instruction.newApplicationBudgetTarget
                + wormhole.messageFee();
            ICoreRelayer.TargetRedeliveryByTxHashParamsSingle memory package = ICoreRelayer
                .TargetRedeliveryByTxHashParamsSingle({
                redeliveryVM: encodedVM,
                sourceEncodedVMs: originalDelivery.encodedVMs,
                relayerRefundAddress: payable(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(targetChain)))
            });
            vm.prank(coreRelayer.fromWormholeFormat(relayProvider.getDeliveryAddress(targetChain)));
            coreRelayer.redeliverSingle{value: budget}(package);
        }
    }

}
