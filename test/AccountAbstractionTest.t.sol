// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {AccountAbstraction} from "../src/AccountAbstraction.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployScript} from "../script/DeployScript.s.sol";
import {SendPackedUser} from "../script/SendPackedUser.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
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

    /// checled by the entry point
    //// validate user will be called by EntryPoint. it will contain the function to execute on My contract
    function testValidateUserOp() public {
        // added some ether for paying the gas fees to the EntryPoint
        vm.deal(address(accountAbstraction), 10 ether);

        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(accountAbstraction),
            AMOUNT
        );

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            300,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp = sendPackedUser
            .genratePackedUserOpWithSignature(
                address(accountAbstraction),
                networkConfig,
                functionCall
            );

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint)
            .getUserOpHash(userOp);
        vm.prank(networkConfig.entryPoint);
        uint256 validateData = accountAbstraction.validateUserOp(
            userOp,
            userOpHash,
            0
        );
        assertEq(validateData, 0);
    }

    function testValidationUserOpWithNoEntryPoint() public {
        // added some ether for paying the gas fees to the EntryPoint
        vm.deal(address(accountAbstraction), 10 ether);

        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(accountAbstraction),
            AMOUNT
        );

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            300,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp = sendPackedUser
            .genratePackedUserOpWithSignature(
                address(accountAbstraction),
                networkConfig,
                functionCall
            );

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint)
            .getUserOpHash(userOp);
        vm.startPrank(address(0x123));
        vm.expectRevert(
            abi.encodeWithSelector(
                AccountAbstraction
                    .AccountAbstraction__NotFromEntryPoint
                    .selector
            )
        );
        accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        vm.stopPrank();
    }

    function testExecuteCommandByOwner() public {
        address dest = address(mockToken);
        vm.startPrank(networkConfig.account);
        uint256 value = 0;
        bytes memory functionCall = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(accountAbstraction),
            AMOUNT
        );
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
            bytes4(keccak256("mint(address,uint256,uint256)")),
            address(accountAbstraction),
            AMOUNT,
            1
        ); 

        /// Act
        vm.startPrank(networkConfig.account);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccountAbstraction.AccountAbstraction__TransferFailed.selector,
                hex""
            )
        );
        accountAbstraction.execute(dest, value, functionCall);
        vm.stopPrank();
    }

    function testEntryPointCanExecuteCommands() public {
        vm.deal(address(accountAbstraction), 10 ether);
        // Arrange
        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(accountAbstraction),
            AMOUNT
        );

        bytes memory functionCall = abi.encodeWithSelector(
            AccountAbstraction.execute.selector,
            // lets assume we are sending to same address
            address(mockToken),
            0,
            innerCall
        );

        // got the signature
        PackedUserOperation memory userOp = sendPackedUser
            .genratePackedUserOpWithSignature(
                address(accountAbstraction),
                networkConfig,
                functionCall
            );

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint)
            .getUserOpHash(userOp);

        // Act
        vm.startPrank(networkConfig.entryPoint);
        uint256 validateData = accountAbstraction.validateUserOp(
            userOp,
            userOpHash,
            0
        );
        accountAbstraction.execute(address(mockToken), 0, innerCall);
        vm.stopPrank();

        assertEq(validateData, 0);
    }

    // a signed userOp 
    // bytes32 _userOphash
    // 
    function testOwnerWithRandomSigner() public {
        // Arrange
        address randomSigner = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        uint256 randomSignerDefaultKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

        // set the function call
        bytes memory innerCall = abi.encodeWithSelector(
            ERC20Mock.mint.selector,
            address(accountAbstraction),
            AMOUNT
        );

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
        PackedUserOperation memory userOp = sendPackedUser.generateAndReturnPackedUserOperation(address(accountAbstraction), nonce, functionCall);
        // converting the above userOp in hash
        bytes32 digest = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);

        // now sign
        (uint8 v,bytes32 r, bytes32 s) = vm.sign(randomSignerDefaultKey, digest);
        // added the signer
        userOp.signature = abi.encodePacked(r,s,v);


        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint)
            .getUserOpHash(userOp);

        vm.prank(networkConfig.entryPoint);
        vm.expectRevert(abi.encodeWithSelector(AccountAbstraction.AccountAbstraction__ValidationFailed.selector));
        uint256 value = accountAbstraction.validateUserOp(userOp, userOpHash, 0);
        // assertEq(signer ,randomSigner);
    }
}
