//
//  ██████╗ ██████╗ ██╗███╗   ██╗██████╗  █████╗ ███████╗███████╗
// ██╔════╝██╔═══██╗██║████╗  ██║██╔══██╗██╔══██╗██╔════╝██╔════╝
// ██║     ██║   ██║██║██╔██╗ ██║██████╔╝███████║███████╗█████╗
// ██║     ██║   ██║██║██║╚██╗██║██╔══██╗██╔══██║╚════██║██╔══╝
// ╚██████╗╚██████╔╝██║██║ ╚████║██████╔╝██║  ██║███████║███████╗
//  ╚═════╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝
//
// This contract allows deposit of multiple validators in one transaction
// SPDX-License-Identifier: Apache-2.0
//
// Coinbase updates:
// Adapted from stakefish Eth2 Batch Deposit contract, removed prior ASCII art
// remove fee collection, pausing and ownership
//
// (BisonDee)
// - Updated to Solidity 0.8+
// - Removed as SafeMath as 0.8+ has overflow checks making SafeMath unnecessary

pragma solidity ^0.8.13;

import {IDepositContract} from "./IDepositContract.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract BatchDeposit {
    address public immutable depositContract;

    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant CREDENTIALS_LENGTH = 32;
    uint256 constant MAX_VALIDATORS = 100;

    // https://eips.ethereum.org/EIPS/eip-165
    // Depost Contract implements IERC165. See https://etherscan.io/address/0x00000000219ab540356cBB839Cbe05303d7705Fa#code
    constructor(address depositContractAddr) {
        require(IERC165(depositContractAddr).supportsInterface(type(IDepositContract).interfaceId), "BatchDeposit: Invalid Deposit Contract");
        depositContract = depositContractAddr;
    }

    /**
     * @dev Performs a batch deposit against the "Eth2.0 Deposit Contract" for multiple validators.
     * @param pubkeys Concatenated BLS12-381 public keys, each 48 bytes long.
     * @param withdrawal_credentials Commitment to a public key for withdrawals, each 32 bytes long.
     * @param signatures Concatenated BLS12-381 signatures, each 96 bytes long.
     *        Each signature corresponds to a validator's deposit data and is used to
     *        verify the authenticity and integrity of the deposit.
     * @param deposit_data_roots Array of SHA-256 hashes of the SSZ-encoded DepositData objects.
     * @param deposit_amounts Array of deposit amounts for each validator, *denominated in wei*.
     */
    function batchDeposit(
        bytes calldata pubkeys,
        bytes calldata withdrawal_credentials,
        bytes calldata signatures,
        bytes32[] calldata deposit_data_roots,
        uint256[] calldata deposit_amounts
    ) external payable {
        uint256 count = deposit_data_roots.length;
        require(count > 0, "BatchDeposit: You should deposit at least one validator");
        require(count <= MAX_VALIDATORS, "BatchDeposit: You can deposit max 100 validators at a time");

        require(pubkeys.length == count * PUBKEY_LENGTH, "BatchDeposit: Pubkey count mismatch");
        require(signatures.length == count * SIGNATURE_LENGTH, "BatchDeposit: Signatures count mismatch");
        require(withdrawal_credentials.length == CREDENTIALS_LENGTH, "BatchDeposit: Withdrawal Credentials count do not match");
        require(deposit_amounts.length == count, "BatchDeposit: Deposit amounts count mismatch");

        // Check that the deposit amounts are valid
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < count; ++i) {
            require(deposit_amounts[i] >= 1 ether, "BatchDeposit: deposit amount too low");
            require(deposit_amounts[i] % 1 gwei == 0, "BatchDeposit: deposit amount not multiple of GWEI");
            // The type casting to uint64 is an early check ultimately mirroring the DepositContract
            uint deposit_amount = msg.value / 1 gwei;
            require(deposit_amount <= type(uint64).max, "BatchDeposit: deposit amount too large");

            totalAmount += deposit_amounts[i];
        }

        require(msg.value == totalAmount, "BatchDeposit: Amount is not aligned with deposit amounts");

        for (uint256 i = 0; i < count; ++i) {
            // These values are calculated directly to avoid stack overflow:
            // bytes memory pubkey = bytes(pubkeys[i*PUBKEY_LENGTH:(i+1)*PUBKEY_LENGTH]);
            // bytes memory signature = bytes(signatures[i*SIGNATURE_LENGTH:(i+1)*SIGNATURE_LENGTH]);

            IDepositContract(depositContract).deposit{value: deposit_amounts[i]}(
                bytes(pubkeys[i * PUBKEY_LENGTH:(i + 1) * PUBKEY_LENGTH]),
                withdrawal_credentials,
                bytes(signatures[i * SIGNATURE_LENGTH:(i + 1) * SIGNATURE_LENGTH]),
                deposit_data_roots[i]
            );
        }
    }
}
