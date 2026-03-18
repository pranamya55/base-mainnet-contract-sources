// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {LibString} from "solmate/utils/LibString.sol";

/**
 * Credit goes to emo.eth / OpenSea, extracted portions of their JSON library for building the OpenEdition
 * JSON metadata.
 * ref: https://github.com/ProjectOpenSea/shipyard-core/blob/main/src/onchain/json.sol
 */

/**
 * @title JSON
 * @author emo.eth
 * @notice TODO: overrides for common types that automatically stringify
 */
library Json {
    string private constant NULL = "";

    using LibString for string;

    /**
     * @notice enclose a string in {braces}
     *         Note: does not escape quotes in value
     * @param  value string to enclose in braces
     * @return string of {value}
     */
    function object(string memory value) internal pure returns (string memory) {
        return string.concat("{", value, "}");
    }

    /**
     * @notice enclose a string in [brackets]
     *         Note: does not escape quotes in value
     * @param value string to enclose in brackets
     * @return string of [value]
     */
    function array(string memory value) internal pure returns (string memory) {
        return string.concat("[", value, "]");
    }

    /**
     * @notice enclose name and value with quotes, and place a colon "between":"them".
     *         Note: escapes quotes in name and value
     * @param name name of property
     * @param value value of property
     * @return string of "name":"value"
     */
    function property(string memory name, string memory value) internal pure returns (string memory) {
        return string.concat('"', escapeJSON(name, false), '":"', escapeJSON(value, false), '"');
    }

    function intProperty(string memory name, string memory value) internal pure returns (string memory) {
        return string.concat('"', escapeJSON(name, false), '":', escapeJSON(value, false), "");
    }

    /**
     * @notice enclose name with quotes, but not rawValue, and place a colon "between":them
     *         Note: escapes quotes in name, but not value (which may itself be a JSON object, array, etc)
     * @param name name of property
     * @param rawValue raw value of property, which will not be enclosed in quotes
     * @return string of "name":value
     */
    function rawProperty(string memory name, string memory rawValue) internal pure returns (string memory) {
        return string.concat('"', escapeJSON(name, false), '":', rawValue);
    }

    /**
     * @notice comma-join an array of properties and {"enclose":"them","in":"braces"}
     *         Note: does not escape quotes in properties, as it assumes they are already escaped
     * @param properties array of '"name":"value"' properties to join
     * @return string of {"name":"value","name":"value",...}
     */
    function objectOf(string[] memory properties) internal pure returns (string memory) {
        return object(_commaJoin(properties));
    }

    /**
     * @notice comma-join an array of strings
     * @param values array of strings to join
     * @return string of value,value,...
     */
    function _commaJoin(string[] memory values) internal pure returns (string memory) {
        return _join(values, ",");
    }

    /**
     * @notice join an array of strings with a specified separator
     * @param values array of strings to join
     * @param separator separator to join with
     * @return string of value<separator>value<separator>...
     */
    function _join(string[] memory values, string memory separator) internal pure returns (string memory) {
        if (values.length == 0) {
            return NULL;
        }
        string memory result = values[0];
        for (uint256 i = 1; i < values.length; ++i) {
            result = string.concat(result, separator, values[i]);
        }
        return result;
    }

    /**
     * @dev Extracted from solady/utils/LibString.sol
     */
    function escapeJSON(string memory s, bool addDoubleQuotes) internal pure returns (string memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            let end := add(s, mload(s))
            result := add(mload(0x40), 0x20)
            if addDoubleQuotes {
                mstore8(result, 34)
                result := add(1, result)
            }
            // Store "\\u0000" in scratch space.
            // Store "0123456789abcdef" in scratch space.
            // Also, store `{0x08:"b", 0x09:"t", 0x0a:"n", 0x0c:"f", 0x0d:"r"}`.
            // into the scratch space.
            mstore(0x15, 0x5c75303030303031323334353637383961626364656662746e006672)
            // Bitmask for detecting `["\"","\\"]`.
            let e := or(shl(0x22, 1), shl(0x5c, 1))
            for {} iszero(eq(s, end)) {} {
                s := add(s, 1)
                let c := and(mload(s), 0xff)
                if iszero(lt(c, 0x20)) {
                    if iszero(and(shl(c, 1), e)) {
                        // Not in `["\"","\\"]`.
                        mstore8(result, c)
                        result := add(result, 1)
                        continue
                    }
                    mstore8(result, 0x5c) // "\\".
                    mstore8(add(result, 1), c)
                    result := add(result, 2)
                    continue
                }
                if iszero(and(shl(c, 1), 0x3700)) {
                    // Not in `["\b","\t","\n","\f","\d"]`.
                    mstore8(0x1d, mload(shr(4, c))) // Hex value.
                    mstore8(0x1e, mload(and(c, 15))) // Hex value.
                    mstore(result, mload(0x19)) // "\\u00XX".
                    result := add(result, 6)
                    continue
                }
                mstore8(result, 0x5c) // "\\".
                mstore8(add(result, 1), mload(add(c, 8)))
                result := add(result, 2)
            }
            if addDoubleQuotes {
                mstore8(result, 34)
                result := add(1, result)
            }
            let last := result
            mstore(last, 0) // Zeroize the slot after the string.
            result := mload(0x40)
            mstore(result, sub(last, add(result, 0x20))) // Store the length.
            mstore(0x40, add(last, 0x20)) // Allocate the memory.
        }
    }
}
