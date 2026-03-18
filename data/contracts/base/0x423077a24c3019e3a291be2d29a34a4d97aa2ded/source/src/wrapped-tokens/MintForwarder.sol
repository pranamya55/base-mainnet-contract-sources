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
pragma solidity 0.8.6;

import {MintUtil} from "./MintUtil.sol";
import {RateLimit} from "./RateLimit.sol";

/**
 * @title MintForwarder
 * @dev Forwarding contract to ERC20 tokens with mint functionality
 */
contract MintForwarder is RateLimit {
    address public tokenContract;
    bool internal initialized;

    event Mint(address indexed minter, address indexed to, uint256 amount);

    /**
     * @dev Function to initialize the contract
     * @param newOwner The address of the owner of the mint contract
     * @param newTokenContract The address of the token contract for which this contract mints
     */
    function initialize(address newOwner, address newTokenContract) external onlyOwner {
        require(!initialized, "MintForwarder: contract is already initialized");
        require(newOwner != address(0), "MintForwarder: owner is the zero address");
        require(newTokenContract != address(0), "MintForwarder: tokenContract is the zero address");
        transferOwnership(newOwner);
        tokenContract = newTokenContract;
        initialized = true;
    }

    /**
     * @dev Rate limited function to mint tokens
     *  @param _to The address that will receive the minted tokens.
     * @param _amount The amount of tokens to mint. Must be less than or equal
     * to the allowance of the caller.
     */
    function mint(address _to, uint256 _amount) external onlyCallers {
        require(_to != address(0), "MintForwarder: cannot mint to the zero address");
        require(_amount > 0, "MintForwarder: mint amount not greater than 0");

        _replenishAllowance(msg.sender);

        require(_amount <= allowances[msg.sender], "MintForwarder: mint amount exceeds caller allowance");

        allowances[msg.sender] = allowances[msg.sender] - _amount;

        MintUtil.safeMint(_to, _amount, tokenContract);
        emit Mint(msg.sender, _to, _amount);
    }
}
