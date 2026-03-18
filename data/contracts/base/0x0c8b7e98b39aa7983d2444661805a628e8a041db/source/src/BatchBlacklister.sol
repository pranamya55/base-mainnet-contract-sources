/**
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2024 Coinbase, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

pragma solidity >=0.8.6;

import {Address} from "@openzeppelin4.2.0/contracts/utils/Address.sol";

contract BatchBlacklister {
    address public immutable blacklister;

    bytes4 private constant _BLACKLIST_SELECTOR = bytes4(keccak256("blacklist(address)"));

    constructor(address _blacklister) {
        blacklister = _blacklister;
    }

     modifier onlyBlacklister() {
        require(msg.sender == blacklister, "BlacklisterOnly: caller is not the blacklister");
        _;
    }

    /// @notice Blacklists a list of addresses on the given FiatToken contract
    ///
    /// @param tokenContract The token contract where the blacklisting takes place
    /// @param addressesToBlacklist List of addresses that will be blacklisted on the token contract
    function blacklistAddresses(address tokenContract, address[] calldata addressesToBlacklist) external onlyBlacklister {
        for (uint256 i; i < addressesToBlacklist.length; i++) {
            address addressToBlacklist = addressesToBlacklist[i]; 

            bytes memory data = abi.encodeWithSelector(_BLACKLIST_SELECTOR, addressToBlacklist);
            Address.functionCall(tokenContract, data, "BatchBlacklister: blacklist failed");
        }
    }
}
