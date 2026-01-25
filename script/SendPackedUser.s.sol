// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {INonceManager} from "@account-abstraction/contracts/interfaces/INonceManager.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Script} from "forge-std/Script.sol";
import {constantForContract} from "./HelperConfig.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
contract SendPackedUser is Script,constantForContract{
    function run() public {
        
    }
    function genratePackedUserOpWithSignature(address accountAbstraction , HelperConfig.NetworkConfig memory config,bytes memory callData) public view  returns(PackedUserOperation memory){
        // nonce
        uint256 nonce = INonceManager(config.entryPoint).getNonce(accountAbstraction , 0);
        PackedUserOperation memory userOp = _generateAndReturnPackedUserOperation(accountAbstraction ,nonce,callData);
        bytes32 digest = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        uint8 v;
        bytes32 r;
        bytes32 s;
        if(block.chainid == ANVIL_CHAIN_ID){
         (v,r,s) = vm.sign(ANVIL_DEFAULT_KEY , digest);   
        }else {
          (v,r,s) = vm.sign(config.account , digest);
        }
        userOp.signature = abi.encodePacked(r,s,v);
        return userOp;
    }
    function _generateAndReturnPackedUserOperation(address sender,uint256 nonce,bytes memory callData) internal pure returns(PackedUserOperation memory){
        uint128 verificationGasLimit = 100000; // 100k gas
        uint128 callGasLimit = 200000; // 200k gas
        uint128 maxPriorityFeePerGas = 1e9; // 1 gwei
        uint128 maxFeePerGas = 10e9; // 10 gwei
        return PackedUserOperation({
            sender : sender,
            nonce : nonce,
            initCode : hex"",
            callData :  callData,
            accountGasLimits: bytes32((uint256(verificationGasLimit) << 128) | uint256(callGasLimit)),
            preVerificationGas: 50000,
            gasFees: bytes32((uint256(maxPriorityFeePerGas) << 128) | uint256(maxFeePerGas)),
            paymasterAndData: hex"",
            signature: hex""
        });

    }
}