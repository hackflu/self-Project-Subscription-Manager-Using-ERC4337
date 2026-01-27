// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAccount} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "@account-abstraction/contracts/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    AutomationCompatibleInterface
} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

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
contract AccountAbstraction is IAccount, Ownable, AutomationCompatibleInterface {
    /*//////////////////////////////////////////////////////////////
                                  ERROR
    //////////////////////////////////////////////////////////////*/
    error AccountAbstraction__ValidationFailed();
    error AccountAbstraction__NotFromEntryPoint();
    error AccountAbstraction__NonceIsOutOfMax();
    error AccountAbstraction__NotFromEntryPointOrOwner();
    error AccountAbstraction__TransferFailed(bytes);
    error AccountAbsctraction__SubscriptionIsActive();
    error AccountAbstraction__SubcriptionIsInvalid(uint256);
    error AccountAbstraction__CheckUpKeepNotNeeded();
    error AccountAbstraction__BeneficiaryIsZero();
    error AccountAbstraction__TokenAddrIsZero();
    error AccountAbstraction__AmountIsZero();
    error AccountAbstraction__ExecuteTimeIsZero();
    error AccountAbstraction__CannotBeLessThaExecuteTime();

    /*//////////////////////////////////////////////////////////////
                            TYPE DECLERATION
    //////////////////////////////////////////////////////////////*/
    struct SubscriptionManager {
        address beneficiary; // Who receives the funds (the merchant/service)
        address token; // The ERC20 token used for payment (USDC, DAI, etc.)
        uint256 amount; // Amount to be paid per period
        uint256 intervalOf; // Calculated timestamp for the next window
        uint256 executeTime; // When the subscription actually begins
        bool active; // Is the subscription currently live?
        uint256 subId; // to tack the subId
    }
    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    IEntryPoint public immutable i_entryPoint;
    mapping(uint256 => SubscriptionManager) public trackSubscription;
    uint256 public totalSubscription;
    uint256 public constant BATCH_SIZE = 10;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(_entryPoint);
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event SubscriptionCreated(address indexed, uint256, uint256, uint256);
    event SubscriptionCancelled(bool, uint256);
    event SubscriptionFailed(uint256, bool);
    event SubscriptionExecuted(uint256, bool);
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
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
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

    function createSubscription(
        address beneficiary,
        address token,
        uint256 amount,
        uint256 executeTime,
        uint256 intervalOf
    ) external requireByEntryPointOrOwner returns (uint256 subId) {
        if(beneficiary == address(0)){
            revert AccountAbstraction__BeneficiaryIsZero();
        }
        if(token == address(0)){
            revert AccountAbstraction__TokenAddrIsZero();
        }
        if(amount == 0){
            revert AccountAbstraction__AmountIsZero();
        }
        if(executeTime == 0){
            revert AccountAbstraction__ExecuteTimeIsZero();
        }
        if(intervalOf < executeTime){
            revert AccountAbstraction__CannotBeLessThaExecuteTime();
        }
        subId = totalSubscription + 1;
        totalSubscription++;
        SubscriptionManager storage subscriptionManager = trackSubscription[subId];
        subscriptionManager.beneficiary = beneficiary;
        subscriptionManager.token = token;
        subscriptionManager.amount = amount;
        subscriptionManager.intervalOf = intervalOf;
        subscriptionManager.executeTime = block.timestamp + executeTime;
        subscriptionManager.subId = subId; // Assign the current subId to the struct field

        subscriptionManager.active = true;
        emit SubscriptionCreated(token, subId, amount, executeTime);
    }

    /**
     * @notice this function is used to execute other task (Note : not used for subscription)
     * @param dest the destination address
     * @param _amount the amount to send
     * @param functionCall function to execute on the destination address
     */
    function execute(address dest, uint256 _amount, bytes calldata functionCall) public requireByEntryPointOrOwner {
        // which mean the address will have the fallback function and receive function
        (bool success, bytes memory data) = dest.call{value: _amount}(functionCall);
        if (!success) {
            revert AccountAbstraction__TransferFailed(data);
        }
    }

    function checkUpkeep(
        bytes calldata /*checkData*/
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256[] memory transactionBatch = new uint256[](BATCH_SIZE);
        uint256 count = 0;
        for (uint256 i = 1; i <= totalSubscription; i++) {
            if (trackSubscription[i].active == true) {
                if (block.timestamp >= trackSubscription[i].executeTime) {
                    transactionBatch[count] = i;
                    count++;
                }
            }
        }
        if (count == 0) {
            return (false, "0x0");
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            result[j] = transactionBatch[j];
        }
        upkeepNeeded = true;
        performData = abi.encode(result);
    }

    function performUpkeep(bytes calldata performData) external override {
        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            SubscriptionManager storage subscription = trackSubscription[subscriptionIds[i]];
            bytes memory functionCall = _createFunctionCall(subscriptionIds[i]);
            (bool success,) = subscription.token.call{value: 0}(functionCall);
            if (success) {
                subscription.executeTime = block.timestamp + subscription.intervalOf;
                emit SubscriptionExecuted(subscription.subId, true);
            } else {
                emit SubscriptionFailed(subscription.subId, false);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER CONTROL
    //////////////////////////////////////////////////////////////*/
    function cancelSubscription(uint256 subId) external requireByEntryPointOrOwner {
        if(subId > totalSubscription || subId == 0){
            revert AccountAbstraction__SubcriptionIsInvalid(subId);
        }
        
        if (trackSubscription[subId].active != true) {
            revert AccountAbstraction__SubcriptionIsInvalid(subId);
        }
        SubscriptionManager storage sub = trackSubscription[subId];
        sub.active = false;
        emit SubscriptionCancelled(true, subId);
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

    function _createFunctionCall(uint256 subId) internal view returns (bytes memory functionCall) {
        address recipitent = trackSubscription[subId].beneficiary;
        uint256 amount = trackSubscription[subId].amount;
        functionCall = abi.encodeWithSelector(IERC20.transfer.selector, recipitent, amount);
    }
}
