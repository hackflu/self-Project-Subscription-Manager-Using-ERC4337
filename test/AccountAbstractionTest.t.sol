// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {AccountAbstraction} from "../src/AccountAbstraction.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployScript} from "../script/DeployScript.s.sol";
import {SendPackedUser} from "../script/SendPackedUser.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {INonceManager} from "@account-abstraction/contracts/interfaces/INonceManager.sol";

contract AccountAbstractionTest is Test {
    DeployScript public deploy;
    AccountAbstraction public accountAbstraction;
    HelperConfig public helper;
    SendPackedUser public sendPackedUser;
    ERC20Mock public mockToken;
    HelperConfig.NetworkConfig public networkConfig;

    uint256 constant AMOUNT = 1e18;

    function setUp() public {
        deploy = new DeployScript();
        (helper, accountAbstraction) = deploy.deployMinimalAccount();
        networkConfig = helper.getConfig();

        sendPackedUser = new SendPackedUser();
        mockToken = new ERC20Mock();
    }

    /*//////////////////////////////////////////////////////////////
                              VALIATEUSEROP
    //////////////////////////////////////////////////////////////*/
    function testValidateUserOp() public {
        // added some ether for paying the gas fees to the EntryPoint
        vm.deal(address(accountAbstraction), 10 ether);

        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountAbstraction), AMOUNT);

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            300,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp =
            sendPackedUser.genratePackedUserOpWithSignature(address(accountAbstraction), networkConfig, functionCall);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);
        vm.prank(networkConfig.entryPoint);
        uint256 validateData = accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        assertEq(validateData, 0);
    }

    function testValidationUserOpWithNoEntryPoint() public {
        // added some ether for paying the gas fees to the EntryPoint
        vm.deal(address(accountAbstraction), 10 ether);

        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountAbstraction), AMOUNT);

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            300,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp =
            sendPackedUser.genratePackedUserOpWithSignature(address(accountAbstraction), networkConfig, functionCall);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);
        vm.startPrank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__NotFromEntryPoint.selector));
        accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        vm.stopPrank();
    }
    /*//////////////////////////////////////////////////////////////
                                 EXECUTE
    //////////////////////////////////////////////////////////////*/

    function testExecuteCommandByOwner() public {
        address dest = address(mockToken);
        vm.startPrank(accountAbstraction.owner());
        uint256 value = 0;
        bytes memory functionCall = abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountAbstraction), AMOUNT);
        accountAbstraction.execute(dest, value, functionCall);
        vm.stopPrank();
        assertEq(mockToken.balanceOf(address(accountAbstraction)), AMOUNT);
    }

    function testExecuteWithMockContract() public {
        // Arrange
        address dest = address(mockToken);

        console.log(dest);
        uint256 value = 0;
        bytes memory functionCall = abi.encodeWithSelector(
            bytes4(keccak256("mint(address,uint256,uint256)")), address(accountAbstraction), AMOUNT, 1
        );

        /// Act
        vm.startPrank(accountAbstraction.owner());
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__TransferFailed.selector, hex""));
        accountAbstraction.execute(dest, value, functionCall);
        vm.stopPrank();
    }

    function testEntryPointCanExecuteCommands() public {
        vm.deal(address(accountAbstraction), 10 ether);
        // Arrange
        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountAbstraction), AMOUNT);

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            0,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp =
            sendPackedUser.genratePackedUserOpWithSignature(address(accountAbstraction), networkConfig, functionCall);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);

        // Act
        vm.startPrank(networkConfig.entryPoint);
        uint256 validateData = accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        accountAbstraction.execute(address(mockToken), 0, innerCall);
        vm.stopPrank();

        assertEq(validateData, 0);
    }

    function testOwnerWithRandomSigner() public {
        // Arrange
        uint256 randomSignerDefaultKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

        // set the function call
        bytes memory innerCall = abi.encodeWithSelector(ERC20Mock.mint.selector, address(accountAbstraction), AMOUNT);

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to dest address
            address(mockToken),
            0,
            innerCall
        );

        // set the nonce
        uint256 nonce = INonceManager(networkConfig.entryPoint).getNonce(address(accountAbstraction), 0);

        // fetching the userop without signer
        PackedUserOperation memory userOp =
            sendPackedUser.generateAndReturnPackedUserOperation(address(accountAbstraction), nonce, functionCall);
        // converting the above userOp in hash
        bytes32 digest = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);

        // now sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randomSignerDefaultKey, digest);
        // added the signer
        userOp.signature = abi.encodePacked(r, s, v);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);

        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__ValidationFailed.selector));
        uint256 value = accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        assertEq(value, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        SUBSCRIPTION METHODS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                         CREATESUBSCRIPTION
    //////////////////////////////////////////////////////////////*/
    function testCreateSubscriptionByEntryPoint() public {
        // Arrange
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        // Act
        vm.prank(networkConfig.entryPoint);
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);

        // Accesst
        uint256 total = accountAbstraction.totalSubscription();
        (
            address _beneficiary,
            address _token,
            uint256 _amount,
            uint256 _intervalOf,
            uint256 _executeTime,
            bool _active,
            uint256 subId
        ) = accountAbstraction.trackSubscription(1);
        assertEq(_beneficiary, beneficiary);
        assertEq(_token, token);
        assertEq(_amount, amount);
        assertEq(_intervalOf, intervalOf);
        assertEq(_executeTime, block.timestamp + executeTime);
        assertEq(_active, true);
        assertEq(subId, 1);
        assertEq(total, 1);
    }

    function testCreateSubscriptionByOwner() public {
        // Arrange
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        // Act
        vm.prank(accountAbstraction.owner());
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);

        // Accesst
        uint256 total = accountAbstraction.totalSubscription();
        (
            address _beneficiary,
            address _token,
            uint256 _amount,
            uint256 _intervalOf,
            uint256 _executeTime,
            bool _active,
            uint256 subId
        ) = accountAbstraction.trackSubscription(1);
        assertEq(_beneficiary, beneficiary);
        assertEq(_token, token);
        assertEq(_amount, amount);
        assertEq(_intervalOf, intervalOf);
        assertEq(_executeTime, block.timestamp + executeTime);
        assertEq(_active, true);
        assertEq(subId, 1);
        assertEq(total, 1);
    }

    function testCreateSubscriptionByRandomAddress() public {
        // Arrange
        address randomOwner = makeAddr("owner");
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        // Act and Assert
        vm.startPrank(randomOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__NotFromEntryPointOrOwner.selector)
        );
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
        vm.stopPrank();
    }

    function testCreateSubscriptionByEntryPointForEvent() public {
        // Arrange
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        // Act and Assert
        vm.startPrank(networkConfig.entryPoint);
        vm.expectEmit(true, false, false, true, address(accountAbstraction));
        emit AccountAbstraction.SubscriptionCreated(token, 1, amount, executeTime);
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
        vm.stopPrank();
    }
    function testCreateSubscriptionBeneficiaryIsZero() public {
        // Arrange
        address beneficiary = address(0);
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__BeneficiaryIsZero.selector));
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }

    function testCreateSubscriptionTokenAddrIsZero() public {
        // Arrange
        address beneficiary = address(0x123);
        address token = address(0);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__TokenAddrIsZero.selector));
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }

    function testCreateSubscriptionAmountIsZero() public {
        // Arrange
        address beneficiary = address(0x123);
        address token = address(mockToken);
        uint256 amount = 0;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__AmountIsZero.selector));
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }

    function testCreateSubscriptionExecutionIsZero() public {
        // Arrange
        address beneficiary = address(0x123);
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 0;
        uint256 intervalOf = 30 days;
        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__ExecuteTimeIsZero.selector));
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }

    function testCreateSubscriptionIntervalOfCheck() public {
        // Arrange
        address beneficiary = address(0x123);
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 0;
        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__CannotBeLessThaExecuteTime.selector));
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }

    modifier requireToCreateSubscription(address owner) {
        // Arrange
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;

        vm.prank(owner);
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
        _;
    }
    /*//////////////////////////////////////////////////////////////
                           CANCEL SUBSCRIPTION
    //////////////////////////////////////////////////////////////*/

    function testCancelSubscription() public requireToCreateSubscription(networkConfig.entryPoint) {
        // Act
        vm.prank(networkConfig.entryPoint);
        accountAbstraction.cancelSubscription(1);
        (,,,,, bool active,) = accountAbstraction.trackSubscription(1);

        // assert
        assertEq(active, false);
    }

    function testCancelSubscriptionWithEvent() public requireToCreateSubscription(accountAbstraction.owner()) {
        // Act
        vm.prank(accountAbstraction.owner());
        vm.expectEmit(false, false, false, true, address(accountAbstraction));
        emit AccountAbstraction.SubscriptionCancelled(true, 1);
        // Assert
        accountAbstraction.cancelSubscription(1);
        (,,,,, bool active,) = accountAbstraction.trackSubscription(1);
        assertEq(active, false);
    }

    function testCancelSubscriptionByRandomAddress() public requireToCreateSubscription(accountAbstraction.owner()) {
        // Arrange
        address randomOwner = makeAddr("owner");
        // Act and Assert
        vm.startPrank(randomOwner);
        vm.expectRevert(
            abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__NotFromEntryPointOrOwner.selector)
        );
        accountAbstraction.cancelSubscription(1);
        vm.stopPrank();
    }

    function testCancelSubscriptionWithSubIdZero() public {
        // Act
        vm.startPrank(accountAbstraction.owner());
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__SubcriptionIsInvalid.selector,0));
        accountAbstraction.cancelSubscription(0);
        vm.stopPrank();
        // Assert
    }

    /*//////////////////////////////////////////////////////////////
                              CHECKUPKEEP
    //////////////////////////////////////////////////////////////*/
    function testCheckUpkeep() public requireToCreateSubscription(accountAbstraction.owner()){
        // Arrange
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, ) = accountAbstraction.checkUpkeep("");
        console.log("UpkeepNeeded value : ",upkeepNeeded);
        // Assert
        assertEq(upkeepNeeded, true);
    }

    function testCheckUpkeepAtSameTime() public requireToCreateSubscription(accountAbstraction.owner()){
        // Act
        (bool upkeepNeeded, ) = accountAbstraction.checkUpkeep("");
        // Assert
        assertEq(upkeepNeeded, false);
    }

    /*//////////////////////////////////////////////////////////////
                              PERFORMUPKEEP
    //////////////////////////////////////////////////////////////*/
    function testPerformUpkeep() public requireToCreateSubscription(accountAbstraction.owner()){

        // Arrange
        mockToken.mint(address(accountAbstraction), AMOUNT);
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, bytes memory performData) = accountAbstraction.checkUpkeep("");

        // Act
        vm.prank(accountAbstraction.owner());
        vm.expectEmit(false, false, false, true , address(accountAbstraction));
        emit AccountAbstraction.SubscriptionExecuted(1, true);
        accountAbstraction.performUpkeep(performData);

        uint256[] memory subscriptionIds = abi.decode(performData, (uint256[]));
        for(uint256 i = 0; i < subscriptionIds.length;i++){
            console.log(subscriptionIds[i]);
        }
        // Assert
        assertEq(upkeepNeeded, true);
    }

    function testPerformUpkeepWithSubscriptionFailed() public requireToCreateSubscription(accountAbstraction.owner()){
        mockToken.mint(address(accountAbstraction), AMOUNT - 1);
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, bytes memory performData) = accountAbstraction.checkUpkeep("");

        // Act
        vm.prank(accountAbstraction.owner());
        vm.expectEmit(false, false, false, true , address(accountAbstraction));
        emit AccountAbstraction.SubscriptionFailed(1, false);
        accountAbstraction.performUpkeep(performData);
        // Assert
        assertEq(upkeepNeeded, true);
    }

    /*//////////////////////////////////////////////////////////////
                          STATE TRANSITION TEST
    //////////////////////////////////////////////////////////////*/
    /**
     * create subscription
     * execute it
     * reExecute it
     */
    function testCreateSubscriptionWithExecute() public requireToCreateSubscription(accountAbstraction.owner()) requireToCreateSubscription(accountAbstraction.owner()){
        mockToken.mint(address(accountAbstraction), AMOUNT + AMOUNT);
        // Arrange
        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, bytes memory performData) = accountAbstraction.checkUpkeep("");
        assertEq(upkeepNeeded, true);   
        console.log("tran : ",accountAbstraction.totalSubscription());
        
        uint256[] memory transactionSubIds = abi.decode(performData , (uint256[]));
        for(uint256 i = 0; i < transactionSubIds.length;i++){
            console.log("data :" ,transactionSubIds[i]);
        }
        performData = abi.encode(transactionSubIds);
        // Act
        vm.prank(accountAbstraction.owner());
        vm.expectEmit(false, false, false, true , address(accountAbstraction));
        emit AccountAbstraction.SubscriptionExecuted(1, true);
        accountAbstraction.performUpkeep(performData);
        // Assert
    }

    function testCreateSubscriptionThenCancelAndExecute() public requireToCreateSubscription(accountAbstraction.owner()){
        // cancelled the subscription
        vm.prank(accountAbstraction.owner());
        accountAbstraction.cancelSubscription(1);

        // check the upkeep
        vm.warp(block.timestamp + 90 days);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = accountAbstraction.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testCreateSubscriptionAndCancelTwice() public requireToCreateSubscription(accountAbstraction.owner()) {
        // cancelled the subscription
        vm.prank(accountAbstraction.owner());
        accountAbstraction.cancelSubscription(1);

        // Cancel Again and check
        vm.prank(accountAbstraction.owner());
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__SubcriptionIsInvalid.selector, 1));
        accountAbstraction.cancelSubscription(1);
    }

    /*//////////////////////////////////////////////////////////////
                            GAS & PERFORMANCE
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice to create single subscription flow and measure the gas
     */
    function testGasCostPriceForSingleSubscription() public  {
        mockToken.mint(address(accountAbstraction), AMOUNT);
        // create subscription
        address beneficiary = makeAddr("beneficiary");
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;
        vm.txGasPrice(20 gwei);

        uint256 gasStart = gasleft();
        vm.prank(accountAbstraction.owner());
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);

        // use checkUpkeep
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, bytes memory performData) = accountAbstraction.checkUpkeep("");
        assertEq(upkeepNeeded, true);

        // performUpkeep
        accountAbstraction.performUpkeep(performData);
        uint256 gasEnd = gasleft();

        uint256 gasUsed = gasStart - gasEnd;
        uint256 costInEth = gasUsed * 20 gwei;

        console.log("Cost in eth : ",costInEth);
    }


    /*//////////////////////////////////////////////////////////////
                             BATCH EXECUTION
    //////////////////////////////////////////////////////////////*/
    function testBatchExecutionOfSubscriptions() public {

        // Arrange
        mockToken.mint(address(accountAbstraction), AMOUNT * 10);
        address token = address(mockToken);
        uint256 amount = AMOUNT;
        uint256 executeTime = 1 days;
        uint256 intervalOf = 30 days;

        for(uint256 i = 1; i <= 10;i++){
            vm.prank(accountAbstraction.owner());
            _createSubscription(address(uint160(i)), token, amount, executeTime, intervalOf);
        }

        // checuUpkeep
        vm.warp(block.timestamp + 2 days);

        (bool upkeepNeeded , bytes memory performData) = accountAbstraction.checkUpkeep("");

        // performUpkeep
        // for(uint256 i = 1; i <= 10;i++){
        
        // }
        // vm.expectEmit(false, false, false, true , address(accountAbstraction));
        // emit AccountAbstraction.SubscriptionExecuted(1, true);
        accountAbstraction.performUpkeep(performData);
        assertEq(upkeepNeeded, true);

    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTION
    //////////////////////////////////////////////////////////////*/
    function _createSubscription(address beneficiary, address token, uint256 amount, uint256 executeTime, uint256 intervalOf) public {
        accountAbstraction.createSubscription(beneficiary, token, amount, executeTime, intervalOf);
    }
}
