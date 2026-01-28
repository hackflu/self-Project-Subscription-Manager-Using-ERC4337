// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ShivToken} from "../src/Token.sol";

contract DeployToken is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy token
        ShivToken token = new ShivToken();

        // Mint tokens to your address
        token.mint(msg.sender, 20_000_000 ether); // adjust amount as needed
        vm.stopBroadcast();
    }
}
