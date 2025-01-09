// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import "forge-std/Test.sol";

import {BeraChainVaultAdapter} from "src/contracts/BeraChainVaultAdapter.sol";


contract BeraChainTest is Test {
    function setUp() public {
        vm.createSelectFork("bsc-main");
    }

    function deployAndInit() private {

    }
        

    
}