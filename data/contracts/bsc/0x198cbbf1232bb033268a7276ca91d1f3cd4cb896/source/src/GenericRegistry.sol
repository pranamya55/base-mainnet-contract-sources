// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IGenericRegistry} from "echo/interfaces/IGenericRegistry.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

contract GenericRegistry is AccessControlEnumerable, IGenericRegistry {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(bytes32 => bytes32) private registry;

    struct Init {
        address admin;
        address manager;
    }

    constructor(Init memory init) {
        _grantRole(DEFAULT_ADMIN_ROLE, init.admin);
        _grantRole(MANAGER_ROLE, init.manager);
    }

    function setBytes32(bytes32 key, bytes32 value) external onlyRole(MANAGER_ROLE) {
        registry[key] = value;
    }

    function setAddress(bytes32 key, address value) external onlyRole(MANAGER_ROLE) {
        registry[key] = bytes32(uint256(uint160(value)));
    }

    function setUint256(bytes32 key, uint256 value) external onlyRole(MANAGER_ROLE) {
        registry[key] = bytes32(value);
    }

    function setInt256(bytes32 key, int256 value) external onlyRole(MANAGER_ROLE) {
        registry[key] = bytes32(uint256(value));
    }

    function setBool(bytes32 key, bool value) external onlyRole(MANAGER_ROLE) {
        registry[key] = bytes32(uint256(value ? 1 : 0));
    }

    function readBytes32(bytes32 key) external view returns (bytes32) {
        return registry[key];
    }

    function readAddress(bytes32 key) external view returns (address) {
        return address(uint160(uint256(registry[key])));
    }

    function readUint256(bytes32 key) external view returns (uint256) {
        return uint256(registry[key]);
    }

    function readInt256(bytes32 key) external view returns (int256) {
        return int256(uint256(registry[key]));
    }

    function readBool(bytes32 key) external view returns (bool) {
        return uint256(registry[key]) == 1;
    }
}
