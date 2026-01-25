// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@account-abstraction/contracts/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AccountAbstraction is BaseAccount {
    /*//////////////////////////////////////////////////////////////
                                  ERROR
    //////////////////////////////////////////////////////////////*/
    error AccountAbstraction__ValidationFailed();
    error AccountAbstraction__NotFromEntryPoint();
    error AccountAbstraction__NonceIsOutOfMax();
    error AccountAbstraction__InvalidNonceFormat();
    error AccountAbstraction__NotFromEntryPointOrOwner();
    
    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint public immutable i_entryPoint;
     
     /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier requireByEntryPoint() {
        if(msg.sender != i_entryPoint){
            AccountAbstraction__NotFromEntryPoint();
        }
        _;
    }

    modifier requireByEntryPointOrOwner() {
        if(msg.sender != i_entryPoint || msg.sender != owner()){
            revert AccountAbstraction__NotFromEntryPointOrOwner();
        }
        _;
    }

     /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _entryPoint) Ownable(msg.sender){
        i_entryPoint = IEntryPoint(_entryPoint);
    }
    /*//////////////////////////////////////////////////////////////
                              EXTERNAL FUNC
    //////////////////////////////////////////////////////////////*/
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData) requireByEntryPoint
    {
        uint256 result = _validateUserOp();
        if (result != 0) {
            revert AccountAbstraction__ValidationFailed();
        }
        _validateNonce(userOp.nonce);
        /// pay to entry point
        _payPrefund(missingAccountFunds);
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
    function _validateSignature(PackedUserOperation calldata _userOp, bytes _userOpHash) internal returns(uint256){
        address signer = ECDSA.recover(_userOpHash, _userOp.signature);
        if(signer != owner){
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }
    /**
     * @notice validate the nonce
     * @param _nonce use the nonce
     */
    function _validateNonce(uint256 _nonce) internal {
        if(nonce > type(uint64).max){
            revert AccountAbstraction__NonceIsOutOfMax();
        }
        if((nonce && type(uint64).max) == 0){
            revert AccountAbstraction__InvalidNonceFormat();
        }
    }
    /**
     * @notice pay the fees to the entryPoint contract
     * @dev the excess entry point is reserved for the future purpose
     * @param _missingAmountFunds amount to pay as fess to EntryPoint
     */
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{
                    value: missingAccountFunds
                }("");
            (success);
            // Ignore failure (its EntryPoint's job to verify, not account.)
        }
    }
}
