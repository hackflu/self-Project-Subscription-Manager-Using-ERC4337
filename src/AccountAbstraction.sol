// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@account-abstraction/contracts/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title  SubscriptionManager
 * @author hackflu
 * @notice A decentralized subscription engine designed for ERC-4337 Account Abstraction.
 * @dev    This contract acts as a recurring payment module. It allows Smart Accounts
 * to authorize automated "pull" payments for ERC-20 tokens based on
 * time-locked intervals.
 * * Architecture:
 * 1. The Smart Account (Wallet) grants an allowance to this contract.
 * 2. The user registers a subscription struct (amount, interval, beneficiary).
 * 3. An off-chain automation (Keeper/Bundler) triggers the execution
 * when `block.timestamp >= lastPayment + interval`.
 */
contract AccountAbstraction is IAccount, Ownable {
    /*//////////////////////////////////////////////////////////////
                                  ERROR
    //////////////////////////////////////////////////////////////*/
    error AccountAbstraction__ValidationFailed();
    error AccountAbstraction__NotFromEntryPoint();
    error AccountAbstraction__NonceIsOutOfMax();
    error AccountAbstraction__NotFromEntryPointOrOwner();
    error AccountAbstraction__TransferFailed(bytes);

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint public immutable i_entryPoint;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireByEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert AccountAbstraction__NotFromEntryPoint();
        }
        _;
    }

    modifier requireByEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) || msg.sender != owner()) {
            revert AccountAbstraction__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNC
    //////////////////////////////////////////////////////////////*/
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        requireByEntryPoint
        returns (uint256 validationData)
    {
        uint256 result = _validateSignature(userOp, userOpHash);
        if (result != 0) {
            revert AccountAbstraction__ValidationFailed();
        }
        _validateNonce(userOp.nonce);
        /// pay to entry point
        _payPrefund(missingAccountFunds);
        return 0;
    }

    function execute(address dest, uint256 _amount, bytes calldata functionCall) public requireByEntryPointOrOwner {
        // which mena the address will have the fallback function and receive function
        (bool success, bytes memory data) = dest.call{value: _amount}(functionCall);
        if (!success) {
            revert AccountAbstraction__TransferFailed(data);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNAL FUNC
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice a internal function responsible for validationg Signature
     * @param _userOp struct containig user Data
     * @param _userOpHash hash of the userOp
     * @return uint256 signal of validation in uint256 form
     */
    function _validateSignature(PackedUserOperation calldata _userOp, bytes32 _userOpHash)
        internal
        view
        returns (uint256)
    {
        address signer = ECDSA.recover(_userOpHash, _userOp.signature);
        if (signer != owner()) {
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    /**
     * @notice validate the nonce
     * @param _nonce use the nonce
     */
    function _validateNonce(uint256 _nonce) internal pure {
        if (_nonce > type(uint64).max) {
            revert AccountAbstraction__NonceIsOutOfMax();
        }
    }

    /**
     * @notice pay the fees to the entryPoint contract
     * @dev the excess entry point is reserved for the future purpose
     * @param missingAccountFunds amount to pay as fess to EntryPoint
     */
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            // Ignore failure (its EntryPoint's job to verify, not account.)
        }
    }
}
