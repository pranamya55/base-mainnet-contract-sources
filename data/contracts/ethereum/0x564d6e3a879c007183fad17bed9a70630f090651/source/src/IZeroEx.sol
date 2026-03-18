// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

interface IZeroEx {
    function getFunctionImplementation(bytes4 _signature) external returns (address);
}

interface IZeroExV2 {
    function exec(address operator, address token, uint256 amount, address payable target, bytes calldata data)
        external
        returns (bytes memory);
}