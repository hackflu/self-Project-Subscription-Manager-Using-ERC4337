// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";

abstract contract constantForContract {
    uint256 constant ARBITRUM_SEPOLIA = 421614;
    uint256 constant ANVIL_CHAIN_ID = 31337;
    address constant BURNER_WALLET = 0x0E6A032eD498633a1FB24b3FA96bF99bBBE4B754;
    address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
}

contract HelperConfig is Script, constantForContract {
    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    mapping(uint256 => NetworkConfig) public config;

    constructor() {
        if (block.chainid == ANVIL_CHAIN_ID) {
            config[block.chainid] = _getAnvilNetworkConfig();
        } else if (block.chainid == ARBITRUM_SEPOLIA) {
            config[block.chainid] = _getArbitrumNetworkConfig();
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return config[block.chainid];
    }

    function _getAnvilNetworkConfig() internal returns (NetworkConfig memory networkConfig) {
        if (config[block.chainid].account != address(0)) {
            return config[block.chainid];
        }
        vm.startBroadcast(ANVIL_DEFAULT_ACCOUNT);
        EntryPoint entryPoint = new EntryPoint();
        vm.stopBroadcast();
        networkConfig = NetworkConfig({entryPoint: address(entryPoint), account: ANVIL_DEFAULT_ACCOUNT});
    }

    function _getArbitrumNetworkConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: BURNER_WALLET});
    }
}
