pragma solidity ^0.8.0;

interface IWormholeReceiver {
    function receiveWormholeMessages(bytes[] memory vaas, bytes[] memory additionalData) external payable;
}