// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IWormhole} from "../src/interfaces/IWormhole.sol";
import {ICoreRelayer} from "../src/interfaces/ICoreRelayer.sol";
import {Spoke} from "../src/spoke/Spoke.sol";

contract ContractScript is Script {
    IWormhole wormhole;
    ICoreRelayer coreRelayer;
    Spoke spoke;

    function setUp() public {
        wormhole = IWormhole(vm.envAddress("TESTING_WORMHOLE_ADDRESS"));
        coreRelayer = ICoreRelayer(vm.envAddress("TESTING_CORERELAYER_ADDRESS"));
    }

    function deploySpoke() public {
        // deploy the HelloWorld contract
        spoke = new Spoke(
            address(wormhole),
            address(coreRelayer),
            vm.envBytes32("TESTING_HUB_ADDRESS"),
            uint16(vm.envUint("TESTING_HUB_CHAINID"))
        );
    }

    function run() public {
        // begin sending transactions
        vm.startBroadcast();

        // Spoke.sol
        deploySpoke();

        // finished
        vm.stopBroadcast();
    }
}
