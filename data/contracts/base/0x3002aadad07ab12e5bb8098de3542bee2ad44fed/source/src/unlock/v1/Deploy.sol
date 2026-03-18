// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Distributor} from "./Distributor.sol";

function newDistributor(address admin, Distributor impl, Distributor.Init memory init) returns (Distributor) {
    // Separate out the initialization so max initcode is not hit.
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), admin, hex"");
    Distributor dist = Distributor(payable(address(proxy)));
    dist.initialize(init);
    return dist;
}
