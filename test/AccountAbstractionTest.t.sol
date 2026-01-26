// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {AccountAbstraction} from "../src/AccountAbstraction.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DeployScript} from "../script/DeployScript.s.sol";
import {SendPackedUser} from "../script/SendPackedUser.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {
    PackedUserOperation
} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {
    IEntryPoint
} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract AccountAbstractionTest is Test {
    DeployScript public deploy;
    AccountAbstraction public accountAbstraction;
    HelperConfig public helper;
    SendPackedUser public sendPackedUser;
    ERC20Mock public mockToken;
    HelperConfig.NetworkConfig public networkConfig;
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
        // calculated the totalSupply for full approveal
        uint256 totalTokenMinted = mockToken.totalSupply();
        // created the network selector
        bytes memory innerCall = abi.encodeWithSelector(
            IERC20.approve.selector,
            address(accountAbstraction),
            totalTokenMinted
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
}
