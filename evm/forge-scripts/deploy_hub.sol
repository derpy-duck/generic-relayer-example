// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {IWormholeRelayer} from "../src/interfaces/IWormholeRelayer.sol";
import {Hub} from "../src/hub/Hub.sol";

contract ContractScript is Script {
    IWormhole wormhole;
    IWormholeRelayer coreRelayer;
    Hub hub;

    function setUp() public {
        wormhole = IWormhole(vm.envAddress("TESTING_WORMHOLE_ADDRESS"));
        coreRelayer = IWormholeRelayer(vm.envAddress("TESTING_CORERELAYER_ADDRESS"));
    }

    function deployHub() public {
        // deploy the HelloWorld contract
        hub = new Hub(
            address(wormhole),
            address(coreRelayer)
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // Hub.sol
        deployHub();

        // finished
        vm.stopBroadcast();
    }
}
