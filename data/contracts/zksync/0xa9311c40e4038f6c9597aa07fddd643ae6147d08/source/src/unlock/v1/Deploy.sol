// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Distributor} from "./Distributor.sol";

function newDistributor(address admin, Distributor impl, Distributor.Init memory init) returns (Distributor) {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
        address(impl), admin, abi.encodeWithSelector(Distributor.initialize.selector, init)
    );
    return Distributor(payable(address(proxy)));
}
