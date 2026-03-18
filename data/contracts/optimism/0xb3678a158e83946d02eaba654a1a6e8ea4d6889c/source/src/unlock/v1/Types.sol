// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice USDC pricing data for a token.
/// @dev The amount of USDC for a given amount of tokens is computed by `amountUSDCUnits = (amountTokenUnits * tokenPriceUSDCNumerator) / tokenPriceUSDCDenominator`.
/// e.g. assuming a 18 decimals for the token, and 6 decimals for usdc,
/// an exchange rate of 1 token = 1234.5678 USDC would mean 1e18 tokenUnits = 1,234,567,800 USDCUnits, corresponding to tokenPriceUSDCNumerator = 1234567800 and tokenPriceUSDCDenominator = 1e18.
/// @param tokenPriceUSDCNumerator The numerator of the token unit price in USDC units.
/// @param tokenPriceUSDCDenominator The denominator of the token unit price in USDC units.
struct Price {
    uint256 tokenPriceUSDCNumerator;
    uint256 tokenPriceUSDCDenominator;
}

library PriceLib {
    function convertTokenToUSDC(Price memory data, uint256 amount) internal pure returns (uint256) {
        return Math.mulDiv(amount, data.tokenPriceUSDCNumerator, data.tokenPriceUSDCDenominator);
    }

    function convertUSDCToToken(Price memory data, uint256 usdcAmount) internal pure returns (uint256) {
        return Math.mulDiv(usdcAmount, data.tokenPriceUSDCDenominator, data.tokenPriceUSDCNumerator);
    }
}

struct ClaimData {
    bytes16 tokenDistributionUUID;
    bytes16 entityUUID;
    address receiver;
    uint256 amount;
    Price price;
    uint256 expiresAt;
}

library ClaimDataLib {
    /// @notice EIP-712 typehash for the ClaimData struct.
    bytes32 constant CLAIM_TYPEHASH = keccak256(
        "ClaimData(bytes16 tokenDistributionUUID,bytes16 entityUUID,address receiver,uint256 amount,Price price,uint256 expiresAt)Price(uint256 tokenPriceUSDCNumerator,uint256 tokenPriceUSDCDenominator)"
    );

    /// @notice EIP-712 typehash for the Price struct.
    bytes32 constant PRICE_TYPEHASH =
        keccak256("Price(uint256 tokenPriceUSDCNumerator,uint256 tokenPriceUSDCDenominator)");

    /// @notice Computes the typed data digest of a ClaimData for a given domain separator.
    function digestTypedData(ClaimData memory data, bytes32 domainSeparator) internal pure returns (bytes32) {
        bytes32 priceHash = keccak256(
            abi.encode(PRICE_TYPEHASH, data.price.tokenPriceUSDCNumerator, data.price.tokenPriceUSDCDenominator)
        );

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_TYPEHASH,
                data.tokenDistributionUUID,
                data.entityUUID,
                data.receiver,
                data.amount,
                priceHash,
                data.expiresAt
            )
        );

        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }
}

struct Claimer {
    bytes16 entityUUID;
    address signer;
    uint64 amountInvestedUSDC;
    bool takeNoCarry;
}

struct CarryWithdrawer {
    bytes16 entityUUID;
    address signer;
    uint16 carryBPS;
}

struct CarryWithdrawalData {
    bytes16 tokenDistributionUUID;
    bytes16 entityUUID;
    address receiver;
    uint256 amount;
    uint256 expiresAt;
}

library CarryWithdrawalLib {
    /// @notice EIP-712 typehash for the CarryWithdrawalData struct.
    bytes32 constant CARRY_WITHDRAWAL_DATA_TYPEHASH = keccak256(
        "CarryWithdrawalData(bytes16 tokenDistributionUUID,bytes16 entityUUID,address receiver,uint256 amount,uint256 expiresAt)"
    );

    /// @notice Computes the typed data digest of a CarryWithdrawalData for a given domain separator.
    function digestTypedData(CarryWithdrawalData memory data, bytes32 domainSeparator)
        internal
        pure
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                CARRY_WITHDRAWAL_DATA_TYPEHASH,
                data.tokenDistributionUUID,
                data.entityUUID,
                data.receiver,
                data.amount,
                data.expiresAt
            )
        );

        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }
}
