// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

interface IGenericRegistry {
    function setBytes32(bytes32 key, bytes32 value) external;
    function setAddress(bytes32 key, address value) external;
    function setUint256(bytes32 key, uint256 value) external;
    function setInt256(bytes32 key, int256 value) external;
    function setBool(bytes32 key, bool value) external;

    function readBytes32(bytes32 key) external view returns (bytes32);
    function readAddress(bytes32 key) external view returns (address);
    function readUint256(bytes32 key) external view returns (uint256);
    function readInt256(bytes32 key) external view returns (int256);
    function readBool(bytes32 key) external view returns (bool);
}
