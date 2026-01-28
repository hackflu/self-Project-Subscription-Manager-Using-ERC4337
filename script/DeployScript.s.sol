// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {AccountAbstraction} from "../src/AccountAbstraction.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployScript is Script {
    AccountAbstraction public accountAbstraction;

    function run() public {
        deployMinimalAccount();
    }

    function deployMinimalAccount() public returns (HelperConfig, AccountAbstraction) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.account);
        accountAbstraction = new AccountAbstraction(config.entryPoint);
        vm.stopBroadcast();
        return (helperConfig, accountAbstraction);
    }
}
