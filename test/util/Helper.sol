// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import "forge-std/Test.sol";

contract Helper is Test {
    function makeAddress(string memory name) public returns (address) {
        address returnValue =  makeAddr(name);
        vm.label(returnValue, name);
        return returnValue;
    }
}