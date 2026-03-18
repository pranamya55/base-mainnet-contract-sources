// SPDX-License-Identifier: MIT
pragma solidity =0.8.15 ^0.8.0 ^0.8.1 ^0.8.15 ^0.8.2;

// lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// lib/base-contracts/src/cannon/libraries/CannonTypes.sol

using LPPMetadataLib for LPPMetaData global;

/// @notice Packed LPP metadata.
/// ┌─────────────┬────────────────────────────────────────────┐
/// │ Bit Offsets │                Description                 │
/// ├─────────────┼────────────────────────────────────────────┤
/// │ [0, 64)     │ Timestamp (Finalized - All data available) │
/// │ [64, 96)    │ Part Offset                                │
/// │ [96, 128)   │ Claimed Size                               │
/// │ [128, 160)  │ Blocks Processed (Inclusive of Padding)    │
/// │ [160, 192)  │ Bytes Processed (Non-inclusive of Padding) │
/// │ [192, 256)  │ Countered                                  │
/// └─────────────┴────────────────────────────────────────────┘
type LPPMetaData is bytes32;

/// @notice LPP metadata UDT extension functions.
library LPPMetadataLib {
    uint256 private constant U64_MASK = 0xFFFFFFFFFFFFFFFF;
    uint256 private constant U32_MASK = 0xFFFFFFFF;

    function setTimestamp(LPPMetaData _self, uint64 _timestamp) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(shl(192, _timestamp), and(_self, not(shl(192, U64_MASK))))
        }
    }

    function setPartOffset(LPPMetaData _self, uint32 _partOffset) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(shl(160, _partOffset), and(_self, not(shl(160, U32_MASK))))
        }
    }

    function setClaimedSize(LPPMetaData _self, uint32 _claimedSize) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(shl(128, _claimedSize), and(_self, not(shl(128, U32_MASK))))
        }
    }

    function setBlocksProcessed(LPPMetaData _self, uint32 _blocksProcessed) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(shl(96, _blocksProcessed), and(_self, not(shl(96, U32_MASK))))
        }
    }

    function setBytesProcessed(LPPMetaData _self, uint32 _bytesProcessed) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(shl(64, _bytesProcessed), and(_self, not(shl(64, U32_MASK))))
        }
    }

    function setCountered(LPPMetaData _self, bool _countered) internal pure returns (LPPMetaData self_) {
        assembly {
            self_ := or(_countered, and(_self, not(U64_MASK)))
        }
    }

    function timestamp(LPPMetaData _self) internal pure returns (uint64 timestamp_) {
        assembly {
            timestamp_ := shr(192, _self)
        }
    }

    function partOffset(LPPMetaData _self) internal pure returns (uint64 partOffset_) {
        assembly {
            partOffset_ := and(shr(160, _self), U32_MASK)
        }
    }

    function claimedSize(LPPMetaData _self) internal pure returns (uint32 claimedSize_) {
        assembly {
            claimedSize_ := and(shr(128, _self), U32_MASK)
        }
    }

    function blocksProcessed(LPPMetaData _self) internal pure returns (uint32 blocksProcessed_) {
        assembly {
            blocksProcessed_ := and(shr(96, _self), U32_MASK)
        }
    }

    function bytesProcessed(LPPMetaData _self) internal pure returns (uint32 bytesProcessed_) {
        assembly {
            bytesProcessed_ := and(shr(64, _self), U32_MASK)
        }
    }

    function countered(LPPMetaData _self) internal pure returns (bool countered_) {
        assembly {
            countered_ := and(_self, U64_MASK)
        }
    }
}

// lib/base-contracts/src/libraries/Features.sol

/// @notice Features is a library that stores feature name constants. Can be used alongside the
///         feature flagging functionality in the SystemConfig contract to selectively enable or
///         disable customizable features of the OP Stack.
library Features {
    /// @notice The ETH_LOCKBOX feature determines if the system is configured to use the
    ///         ETHLockbox contract in the OptimismPortal. When the ETH_LOCKBOX feature is active
    ///         and the ETHLockbox contract has been configured, the OptimismPortal will use the
    ///         ETHLockbox to store ETH instead of storing ETH directly in the portal itself.
    bytes32 internal constant ETH_LOCKBOX = "ETH_LOCKBOX";

    /// @notice The CUSTOM_GAS_TOKEN feature determines if the system is configured to use a custom
    ///         gas token in the OptimismPortal. When the CUSTOM_GAS_TOKEN feature is active, the
    ///         deposits and withdrawals of native ETH are disabled.
    bytes32 internal constant CUSTOM_GAS_TOKEN = "CUSTOM_GAS_TOKEN";
}

// lib/base-contracts/interfaces/dispute/IInitializable.sol

interface IInitializable {
    function initialize() external payable;
}

// lib/base-contracts/interfaces/universal/IOwnable.sol

/// @title IOwnable
/// @notice Interface for Ownable.
interface IOwnable {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external; // nosemgrep

    function __constructor__() external;
}

// lib/base-contracts/interfaces/universal/IReinitializableBase.sol

interface IReinitializableBase {
    error ReinitializableBase_ZeroInitVersion();

    function initVersion() external view returns (uint8);

    // ReinitializerBase is abstract, so it has no constructor in its interface.
    function __constructor__() external;
}

// lib/base-contracts/interfaces/L1/IResourceMetering.sol

interface IResourceMetering {
    struct ResourceParams {
        uint128 prevBaseFee;
        uint64 prevBoughtGas;
        uint64 prevBlockNum;
    }

    struct ResourceConfig {
        uint32 maxResourceLimit;
        uint8 elasticityMultiplier;
        uint8 baseFeeMaxChangeDenominator;
        uint32 minimumBaseFee;
        uint32 systemTxMaxGas;
        uint128 maximumBaseFee;
    }

    error OutOfGas();

    event Initialized(uint8 version);

    function params() external view returns (uint128 prevBaseFee, uint64 prevBoughtGas, uint64 prevBlockNum); // nosemgrep

    function __constructor__() external;
}

// lib/base-contracts/interfaces/universal/ISemver.sol

/// @title ISemver
/// @notice ISemver is a simple contract for ensuring that contracts are
///         versioned using semantic versioning.
interface ISemver {
    /// @notice Getter for the semantic version of the contract. This is not
    ///         meant to be used onchain but instead meant to be used by offchain
    ///         tooling.
    /// @return Semver contract version as a string.
    function version() external view returns (string memory);
}

// lib/lib-keccak/contracts/lib/LibKeccak.sol

/// @title LibKeccak
/// @notice An EVM implementation of the Keccak-f[1600] permutation.
/// @author clabby <https://github.com/clabby>
/// @custom:attribution geohot <https://github.com/geohot>
library LibKeccak {
    /// @notice The block size of the Keccak-f[1600] permutation, 1088 bits (136 bytes).
    uint256 internal constant BLOCK_SIZE_BYTES = 136;

    /// @notice The round constants for the keccak256 hash function. Packed in memory for efficient reading during the
    ///         permutation.
    bytes internal constant ROUND_CONSTANTS = abi.encode(
        0x00000000000000010000000000008082800000000000808a8000000080008000, // r1,r2,r3,r4
        0x000000000000808b000000008000000180000000800080818000000000008009, // r5,r6,r7,r8
        0x000000000000008a00000000000000880000000080008009000000008000000a, // r9,r10,r11,r12
        0x000000008000808b800000000000008b80000000000080898000000000008003, // r13,r14,r15,r16
        0x80000000000080028000000000000080000000000000800a800000008000000a, // r17,r18,r19,r20
        0x8000000080008081800000000000808000000000800000018000000080008008 // r21,r22,r23,r24
    );

    /// @notice A mask for 64-bit values.
    uint64 private constant U64_MASK = 0xFFFFFFFFFFFFFFFF;

    /// @notice The 5x5 state matrix for the keccak-f[1600] permutation.
    struct StateMatrix {
        uint64[25] state;
    }

    /// @notice Performs the Keccak-f[1600] permutation on the given 5x5 state matrix.
    function permutation(StateMatrix memory _stateMatrix) internal pure {
        // Pull the round constants into memory to avoid reallocation in the unrolled permutation loop.
        bytes memory roundConstants = ROUND_CONSTANTS;

        assembly {
            // Add 32 to the state matrix pointer to skip the data location field.
            let stateMatrixPtr := add(_stateMatrix, 0x20)
            let rcPtr := add(roundConstants, 0x20)

            // set a state element in the passed `StateMatrix` struct memory ptr.
            function setStateElem(ptr, idx, data) {
                mstore(add(ptr, shl(0x05, idx)), and(data, U64_MASK))
            }

            // fetch a state element from the passed `StateMatrix` struct memory ptr.
            function stateElem(ptr, idx) -> elem {
                elem := mload(add(ptr, shl(0x05, idx)))
            }

            // 64 bit logical shift
            function shl64(a, b) -> val {
                val := and(shl(a, b), U64_MASK)
            }

            // Performs an indivudual rho + pi computation, to be used in the full `thetaRhoPi` chain.
            function rhoPi(ptr, destIdx, srcIdx, fact, dt) {
                let xs1 := xor(stateElem(ptr, srcIdx), dt)
                let res := xor(shl(fact, xs1), shr(sub(64, fact), xs1))
                setStateElem(ptr, destIdx, res)
            }

            // xor a column in the state matrix
            function xorColumn(ptr, col) -> val {
                val :=
                    xor(
                        xor(xor(stateElem(ptr, col), stateElem(ptr, add(col, 5))), stateElem(ptr, add(col, 10))),
                        xor(stateElem(ptr, add(col, 15)), stateElem(ptr, add(col, 20)))
                    )
            }

            // Performs the `theta`, `rho`, and `pi` steps of the Keccak-f[1600] permutation on
            // the passed `StateMatrix` struct memory ptr.
            function thetaRhoPi(ptr) {
                // Theta
                let C0 := xorColumn(ptr, 0)
                let C1 := xorColumn(ptr, 1)
                let C2 := xorColumn(ptr, 2)
                let C3 := xorColumn(ptr, 3)
                let C4 := xorColumn(ptr, 4)
                let D0 := xor(xor(shl64(1, C1), shr(63, C1)), C4)
                let D1 := xor(xor(shl64(1, C2), shr(63, C2)), C0)
                let D2 := xor(xor(shl64(1, C3), shr(63, C3)), C1)
                let D3 := xor(xor(shl64(1, C4), shr(63, C4)), C2)
                let D4 := xor(xor(shl64(1, C0), shr(63, C0)), C3)

                let xs1 := xor(stateElem(ptr, 1), D1)
                let A1 := xor(shl(1, xs1), shr(63, xs1))

                let _ptr := ptr
                setStateElem(_ptr, 0, xor(stateElem(_ptr, 0), D0))
                rhoPi(_ptr, 1, 6, 44, D1)
                rhoPi(_ptr, 6, 9, 20, D4)
                rhoPi(_ptr, 9, 22, 61, D2)
                rhoPi(_ptr, 22, 14, 39, D4)
                rhoPi(_ptr, 14, 20, 18, D0)
                rhoPi(_ptr, 20, 2, 62, D2)
                rhoPi(_ptr, 2, 12, 43, D2)
                rhoPi(_ptr, 12, 13, 25, D3)
                rhoPi(_ptr, 13, 19, 8, D4)
                rhoPi(_ptr, 19, 23, 56, D3)
                rhoPi(_ptr, 23, 15, 41, D0)
                rhoPi(_ptr, 15, 4, 27, D4)
                rhoPi(_ptr, 4, 24, 14, D4)
                rhoPi(_ptr, 24, 21, 2, D1)
                rhoPi(_ptr, 21, 8, 55, D3)
                rhoPi(_ptr, 8, 16, 45, D1)
                rhoPi(_ptr, 16, 5, 36, D0)
                rhoPi(_ptr, 5, 3, 28, D3)
                rhoPi(_ptr, 3, 18, 21, D3)
                rhoPi(_ptr, 18, 17, 15, D2)
                rhoPi(_ptr, 17, 11, 10, D1)
                rhoPi(_ptr, 11, 7, 6, D2)
                rhoPi(_ptr, 7, 10, 3, D0)
                setStateElem(_ptr, 10, A1)
            }

            // Inner `chi` function, unrolled in `chi` for performance.
            function innerChi(ptr, start) {
                let A0 := stateElem(ptr, start)
                let A1 := stateElem(ptr, add(start, 1))
                let A2 := stateElem(ptr, add(start, 2))
                let A3 := stateElem(ptr, add(start, 3))
                let A4 := stateElem(ptr, add(start, 4))

                setStateElem(ptr, start, xor(A0, and(not(A1), A2)))
                setStateElem(ptr, add(start, 1), xor(A1, and(not(A2), A3)))
                setStateElem(ptr, add(start, 2), xor(A2, and(not(A3), A4)))
                setStateElem(ptr, add(start, 3), xor(A3, and(not(A4), A0)))
                setStateElem(ptr, add(start, 4), xor(A4, and(not(A0), A1)))
            }

            // Performs the `chi` step of the Keccak-f[1600] permutation on the passed `StateMatrix` struct memory ptr
            function chi(ptr) {
                innerChi(ptr, 0)
                innerChi(ptr, 5)
                innerChi(ptr, 10)
                innerChi(ptr, 15)
                innerChi(ptr, 20)
            }

            // Perform the full Keccak-f[1600] permutation on a `StateMatrix` struct memory ptr for a given round.
            function permute(ptr, roundsPtr, round) {
                // Theta, Rho, Pi, Chi
                thetaRhoPi(ptr)
                chi(ptr)
                // Iota
                let roundConst := shr(192, mload(add(roundsPtr, shl(0x03, round))))
                setStateElem(ptr, 0, xor(stateElem(ptr, 0), roundConst))
            }

            // Unroll the permutation loop.
            permute(stateMatrixPtr, rcPtr, 0)
            permute(stateMatrixPtr, rcPtr, 1)
            permute(stateMatrixPtr, rcPtr, 2)
            permute(stateMatrixPtr, rcPtr, 3)
            permute(stateMatrixPtr, rcPtr, 4)
            permute(stateMatrixPtr, rcPtr, 5)
            permute(stateMatrixPtr, rcPtr, 6)
            permute(stateMatrixPtr, rcPtr, 7)
            permute(stateMatrixPtr, rcPtr, 8)
            permute(stateMatrixPtr, rcPtr, 9)
            permute(stateMatrixPtr, rcPtr, 10)
            permute(stateMatrixPtr, rcPtr, 11)
            permute(stateMatrixPtr, rcPtr, 12)
            permute(stateMatrixPtr, rcPtr, 13)
            permute(stateMatrixPtr, rcPtr, 14)
            permute(stateMatrixPtr, rcPtr, 15)
            permute(stateMatrixPtr, rcPtr, 16)
            permute(stateMatrixPtr, rcPtr, 17)
            permute(stateMatrixPtr, rcPtr, 18)
            permute(stateMatrixPtr, rcPtr, 19)
            permute(stateMatrixPtr, rcPtr, 20)
            permute(stateMatrixPtr, rcPtr, 21)
            permute(stateMatrixPtr, rcPtr, 22)
            permute(stateMatrixPtr, rcPtr, 23)
        }
    }

    /// @notice Absorb a fixed-sized block into the sponge.
    function absorb(StateMatrix memory _stateMatrix, bytes memory _input) internal pure {
        assembly {
            // The input must be 1088 bits long.
            if iszero(eq(mload(_input), BLOCK_SIZE_BYTES)) { revert(0, 0) }

            let dataPtr := add(_input, 0x20)
            let statePtr := add(_stateMatrix, 0x20)

            // set a state element in the passed `StateMatrix` struct memory ptr.
            function setStateElem(ptr, idx, data) {
                mstore(add(ptr, shl(0x05, idx)), and(data, U64_MASK))
            }

            // fetch a state element from the passed `StateMatrix` struct memory ptr.
            function stateElem(ptr, idx) -> elem {
                elem := mload(add(ptr, shl(0x05, idx)))
            }

            // Inner sha3 absorb XOR function
            function absorbInner(stateMatrixPtr, inputPtr, idx) {
                let boWord := mload(add(inputPtr, shl(3, idx)))

                let res :=
                    or(
                        or(
                            or(shl(56, byte(7, boWord)), shl(48, byte(6, boWord))),
                            or(shl(40, byte(5, boWord)), shl(32, byte(4, boWord)))
                        ),
                        or(
                            or(shl(24, byte(3, boWord)), shl(16, byte(2, boWord))),
                            or(shl(8, byte(1, boWord)), byte(0, boWord))
                        )
                    )
                setStateElem(stateMatrixPtr, idx, xor(stateElem(stateMatrixPtr, idx), res))
            }

            // Unroll the input XOR loop.
            absorbInner(statePtr, dataPtr, 0)
            absorbInner(statePtr, dataPtr, 1)
            absorbInner(statePtr, dataPtr, 2)
            absorbInner(statePtr, dataPtr, 3)
            absorbInner(statePtr, dataPtr, 4)
            absorbInner(statePtr, dataPtr, 5)
            absorbInner(statePtr, dataPtr, 6)
            absorbInner(statePtr, dataPtr, 7)
            absorbInner(statePtr, dataPtr, 8)
            absorbInner(statePtr, dataPtr, 9)
            absorbInner(statePtr, dataPtr, 10)
            absorbInner(statePtr, dataPtr, 11)
            absorbInner(statePtr, dataPtr, 12)
            absorbInner(statePtr, dataPtr, 13)
            absorbInner(statePtr, dataPtr, 14)
            absorbInner(statePtr, dataPtr, 15)
            absorbInner(statePtr, dataPtr, 16)
        }
    }

    /// @notice Squeezes the final keccak256 digest from the passed `StateMatrix`.
    function squeeze(StateMatrix memory _stateMatrix) internal pure returns (bytes32 hash_) {
        assembly {
            // 64 bit logical shift
            function shl64(a, b) -> val {
                val := and(shl(a, b), U64_MASK)
            }

            // convert a big endian 64-bit value to a little endian 64-bit value.
            function toLE(beVal) -> leVal {
                beVal := or(and(shl64(8, beVal), 0xFF00FF00FF00FF00), and(shr(8, beVal), 0x00FF00FF00FF00FF))
                beVal := or(and(shl64(16, beVal), 0xFFFF0000FFFF0000), and(shr(16, beVal), 0x0000FFFF0000FFFF))
                leVal := or(shl64(32, beVal), shr(32, beVal))
            }

            // fetch a state element from the passed `StateMatrix` struct memory ptr.
            function stateElem(ptr, idx) -> elem {
                elem := mload(add(ptr, shl(0x05, idx)))
            }

            let stateMatrixPtr := add(_stateMatrix, 0x20)
            hash_ :=
                or(
                    or(shl(192, toLE(stateElem(stateMatrixPtr, 0))), shl(128, toLE(stateElem(stateMatrixPtr, 1)))),
                    or(shl(64, toLE(stateElem(stateMatrixPtr, 2))), toLE(stateElem(stateMatrixPtr, 3)))
                )
        }
    }

    /// @notice Pads input data to an even multiple of the Keccak-f[1600] permutation block size, 1088 bits (136 bytes).
    function pad(bytes calldata _data) internal pure returns (bytes memory padded_) {
        assembly {
            padded_ := mload(0x40)

            // Grab the original length of `_data`
            let len := _data.length

            let dataPtr := add(padded_, 0x20)
            let endPtr := add(dataPtr, len)

            // Copy the data into memory.
            calldatacopy(dataPtr, _data.offset, len)

            let modBlockSize := mod(len, BLOCK_SIZE_BYTES)
            switch modBlockSize
            case false {
                // Clean the full padding block. It is possible that this memory is dirty, since solidity sometimes does
                // not update the free memory pointer when allocating memory, for example with external calls. To do
                // this, we read out-of-bounds from the calldata, which will always return 0 bytes.
                calldatacopy(endPtr, calldatasize(), BLOCK_SIZE_BYTES)

                // If the input is a perfect multiple of the block size, then we add a full extra block of padding.
                mstore8(endPtr, 0x01)
                mstore8(sub(add(endPtr, BLOCK_SIZE_BYTES), 0x01), 0x80)

                // Update the length of the data to include the padding.
                mstore(padded_, add(len, BLOCK_SIZE_BYTES))
            }
            default {
                // If the input is not a perfect multiple of the block size, then we add a partial block of padding.
                // This should entail a set bit after the input, followed by as many zero bits as necessary to fill
                // the block, followed by a single 1 bit in the lowest-order bit of the final block.

                let remaining := sub(BLOCK_SIZE_BYTES, modBlockSize)
                let newLen := add(len, remaining)
                let paddedEndPtr := add(dataPtr, newLen)

                // Clean the remainder to ensure that the intermediate data between the padding bits is 0. It is
                // possible that this memory is dirty, since solidity sometimes does not update the free memory pointer
                // when allocating memory, for example with external calls. To do this, we read out-of-bounds from the
                // calldata, which will always return 0 bytes.
                let partialRemainder := sub(paddedEndPtr, endPtr)
                calldatacopy(endPtr, calldatasize(), partialRemainder)

                // Store the padding bits.
                mstore8(sub(paddedEndPtr, 0x01), 0x80)
                mstore8(endPtr, or(byte(0x00, mload(endPtr)), 0x01))

                // Update the length of the data to include the padding. The length should be a multiple of the
                // block size after this.
                mstore(padded_, newLen)
            }

            // Update the free memory pointer.
            mstore(0x40, add(padded_, and(add(mload(padded_), 0x3F), not(0x1F))))
        }
    }

    /// @notice Pads input data to an even multiple of the Keccak-f[1600] permutation block size, 1088 bits (136 bytes).
    function padMemory(bytes memory _data) internal pure returns (bytes memory padded_) {
        assembly {
            padded_ := mload(0x40)

            // Grab the original length of `_data`
            let len := mload(_data)

            let dataPtr := add(padded_, 0x20)
            let endPtr := add(dataPtr, len)

            // Copy the data.
            let originalDataPtr := add(_data, 0x20)
            for { let i := 0x00 } lt(i, len) { i := add(i, 0x20) } {
                mstore(add(dataPtr, i), mload(add(originalDataPtr, i)))
            }

            let modBlockSize := mod(len, BLOCK_SIZE_BYTES)
            switch modBlockSize
            case false {
                // Clean the full padding block. It is possible that this memory is dirty, since solidity sometimes does
                // not update the free memory pointer when allocating memory, for example with external calls. To do
                // this, we read out-of-bounds from the calldata, which will always return 0 bytes.
                calldatacopy(endPtr, calldatasize(), BLOCK_SIZE_BYTES)

                // If the input is a perfect multiple of the block size, then we add a full extra block of padding.
                mstore8(sub(add(endPtr, BLOCK_SIZE_BYTES), 0x01), 0x80)
                mstore8(endPtr, 0x01)

                // Update the length of the data to include the padding.
                mstore(padded_, add(len, BLOCK_SIZE_BYTES))
            }
            default {
                // If the input is not a perfect multiple of the block size, then we add a partial block of padding.
                // This should entail a set bit after the input, followed by as many zero bits as necessary to fill
                // the block, followed by a single 1 bit in the lowest-order bit of the final block.

                let remaining := sub(BLOCK_SIZE_BYTES, modBlockSize)
                let newLen := add(len, remaining)
                let paddedEndPtr := add(dataPtr, newLen)

                // Clean the remainder to ensure that the intermediate data between the padding bits is 0. It is
                // possible that this memory is dirty, since solidity sometimes does not update the free memory pointer
                // when allocating memory, for example with external calls. To do this, we read out-of-bounds from the
                // calldata, which will always return 0 bytes.
                let partialRemainder := sub(paddedEndPtr, endPtr)
                calldatacopy(endPtr, calldatasize(), partialRemainder)

                // Store the padding bits.
                mstore8(sub(paddedEndPtr, 0x01), 0x80)
                mstore8(endPtr, or(byte(0x00, mload(endPtr)), 0x01))

                // Update the length of the data to include the padding. The length should be a multiple of the
                // block size after this.
                mstore(padded_, newLen)
            }

            // Update the free memory pointer.
            mstore(0x40, add(padded_, and(add(mload(padded_), 0x3F), not(0x1F))))
        }
    }
}

// lib/base-contracts/src/dispute/lib/LibPosition.sol

using LibPosition for Position global;

/// @notice A `Position` represents a position of a claim within the game tree.
/// @dev This is represented as a "generalized index" where the high-order bit
/// is the level in the tree and the remaining bits is a unique bit pattern, allowing
/// a unique identifier for each node in the tree. Mathematically, it is calculated
/// as 2^{depth} + indexAtDepth.
type Position is uint128;

/// @title LibPosition
/// @notice This library contains helper functions for working with the `Position` type.
library LibPosition {
    /// @notice the `MAX_POSITION_BITLEN` is the number of bits that the `Position` type, and the implementation of
    ///         its behavior within this library, can safely support.
    uint8 internal constant MAX_POSITION_BITLEN = 126;

    /// @notice Computes a generalized index (2^{depth} + indexAtDepth).
    /// @param _depth The depth of the position.
    /// @param _indexAtDepth The index at the depth of the position.
    /// @return position_ The computed generalized index.
    function wrap(uint8 _depth, uint128 _indexAtDepth) internal pure returns (Position position_) {
        assembly {
            // gindex = 2^{_depth} + _indexAtDepth
            position_ := add(shl(_depth, 1), _indexAtDepth)
        }
    }

    /// @notice Pulls the `depth` out of a `Position` type.
    /// @param _position The generalized index to get the `depth` of.
    /// @return depth_ The `depth` of the `position` gindex.
    /// @custom:attribution Solady <https://github.com/Vectorized/Solady>
    function depth(Position _position) internal pure returns (uint8 depth_) {
        // Return the most significant bit offset, which signifies the depth of the gindex.
        assembly {
            depth_ := or(depth_, shl(6, lt(0xffffffffffffffff, shr(depth_, _position))))
            depth_ := or(depth_, shl(5, lt(0xffffffff, shr(depth_, _position))))

            // For the remaining 32 bits, use a De Bruijn lookup.
            _position := shr(depth_, _position)
            _position := or(_position, shr(1, _position))
            _position := or(_position, shr(2, _position))
            _position := or(_position, shr(4, _position))
            _position := or(_position, shr(8, _position))
            _position := or(_position, shr(16, _position))

            depth_ := or(
                depth_,
                byte(
                    shr(251, mul(_position, shl(224, 0x07c4acdd))),
                    0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f
                )
            )
        }
    }

    /// @notice Pulls the `indexAtDepth` out of a `Position` type.
    ///         The `indexAtDepth` is the left/right index of a position at a specific depth within
    ///         the binary tree, starting from index 0. For example, at gindex 2, the `depth` = 1
    ///         and the `indexAtDepth` = 0.
    /// @param _position The generalized index to get the `indexAtDepth` of.
    /// @return indexAtDepth_ The `indexAtDepth` of the `position` gindex.
    function indexAtDepth(Position _position) internal pure returns (uint128 indexAtDepth_) {
        // Return bits p_{msb-1}...p_{0}. This effectively pulls the 2^{depth} out of the gindex,
        // leaving only the `indexAtDepth`.
        uint256 msb = depth(_position);
        assembly {
            indexAtDepth_ := sub(_position, shl(msb, 1))
        }
    }

    /// @notice Get the left child of `_position`.
    /// @param _position The position to get the left position of.
    /// @return left_ The position to the left of `position`.
    function left(Position _position) internal pure returns (Position left_) {
        assembly {
            left_ := shl(1, _position)
        }
    }

    /// @notice Get the right child of `_position`
    /// @param _position The position to get the right position of.
    /// @return right_ The position to the right of `position`.
    function right(Position _position) internal pure returns (Position right_) {
        assembly {
            right_ := or(1, shl(1, _position))
        }
    }

    /// @notice Get the parent position of `_position`.
    /// @param _position The position to get the parent position of.
    /// @return parent_ The parent position of `position`.
    function parent(Position _position) internal pure returns (Position parent_) {
        assembly {
            parent_ := shr(1, _position)
        }
    }

    /// @notice Get the deepest, right most gindex relative to the `position`. This is equivalent to
    ///         calling `right` on a position until the maximum depth is reached.
    /// @param _position The position to get the relative deepest, right most gindex of.
    /// @param _maxDepth The maximum depth of the game.
    /// @return rightIndex_ The deepest, right most gindex relative to the `position`.
    function rightIndex(Position _position, uint256 _maxDepth) internal pure returns (Position rightIndex_) {
        uint256 msb = depth(_position);
        assembly {
            let remaining := sub(_maxDepth, msb)
            rightIndex_ := or(shl(remaining, _position), sub(shl(remaining, 1), 1))
        }
    }

    /// @notice Get the deepest, right most trace index relative to the `position`. This is
    ///         equivalent to calling `right` on a position until the maximum depth is reached and
    ///         then finding its index at depth.
    /// @param _position The position to get the relative trace index of.
    /// @param _maxDepth The maximum depth of the game.
    /// @return traceIndex_ The trace index relative to the `position`.
    function traceIndex(Position _position, uint256 _maxDepth) internal pure returns (uint256 traceIndex_) {
        uint256 msb = depth(_position);
        assembly {
            let remaining := sub(_maxDepth, msb)
            traceIndex_ := sub(or(shl(remaining, _position), sub(shl(remaining, 1), 1)), shl(_maxDepth, 1))
        }
    }

    /// @notice Gets the position of the highest ancestor of `_position` that commits to the same
    ///         trace index.
    /// @param _position The position to get the highest ancestor of.
    /// @return ancestor_ The highest ancestor of `position` that commits to the same trace index.
    function traceAncestor(Position _position) internal pure returns (Position ancestor_) {
        // Create a field with only the lowest unset bit of `_position` set.
        Position lsb;
        assembly {
            lsb := and(not(_position), add(_position, 1))
        }
        // Find the index of the lowest unset bit within the field.
        uint256 msb = depth(lsb);
        // The highest ancestor that commits to the same trace index is the original position
        // shifted right by the index of the lowest unset bit.
        assembly {
            let a := shr(msb, _position)
            // Bound the ancestor to the minimum gindex, 1.
            ancestor_ := or(a, iszero(a))
        }
    }

    /// @notice Gets the position of the highest ancestor of `_position` that commits to the same
    ///         trace index, while still being below `_upperBoundExclusive`.
    /// @param _position The position to get the highest ancestor of.
    /// @param _upperBoundExclusive The exclusive upper depth bound, used to inform where to stop in order
    ///                             to not escape a sub-tree.
    /// @return ancestor_ The highest ancestor of `position` that commits to the same trace index.
    function traceAncestorBounded(
        Position _position,
        uint256 _upperBoundExclusive
    )
        internal
        pure
        returns (Position ancestor_)
    {
        // This function only works for positions that are below the upper bound.
        if (_position.depth() <= _upperBoundExclusive) {
            assembly {
                // Revert with `ClaimAboveSplit()`
                mstore(0x00, 0xb34b5c22)
                revert(0x1C, 0x04)
            }
        }

        // Grab the global trace ancestor.
        ancestor_ = traceAncestor(_position);

        // If the ancestor is above or at the upper bound, shift it to be below the upper bound.
        // This should be a special case that only covers positions that commit to the final leaf
        // in a sub-tree.
        if (ancestor_.depth() <= _upperBoundExclusive) {
            ancestor_ = ancestor_.rightIndex(_upperBoundExclusive + 1);
        }
    }

    /// @notice Get the move position of `_position`, which is the left child of:
    ///         1. `_position` if `_isAttack` is true.
    ///         2. `_position | 1` if `_isAttack` is false.
    /// @param _position The position to get the relative attack/defense position of.
    /// @param _isAttack Whether or not the move is an attack move.
    /// @return move_ The move position relative to `position`.
    function move(Position _position, bool _isAttack) internal pure returns (Position move_) {
        assembly {
            move_ := shl(1, or(iszero(_isAttack), _position))
        }
    }

    /// @notice Get the value of a `Position` type in the form of the underlying uint128.
    /// @param _position The position to get the value of.
    /// @return raw_ The value of the `position` as a uint128 type.
    function raw(Position _position) internal pure returns (uint128 raw_) {
        assembly {
            raw_ := _position
        }
    }
}

// lib/base-contracts/src/universal/ReinitializableBase.sol

/// @title ReinitializableBase
/// @notice A base contract for reinitializable contracts that exposes a version number.
abstract contract ReinitializableBase {
    /// @notice Thrown when the initialization version is zero.
    error ReinitializableBase_ZeroInitVersion();

    /// @notice Current initialization version.
    uint8 internal immutable INIT_VERSION;

    /// @param _initVersion Current initialization version.
    constructor(uint8 _initVersion) {
        // Sanity check, we should never have a zero init version.
        if (_initVersion == 0) revert ReinitializableBase_ZeroInitVersion();
        INIT_VERSION = _initVersion;
    }

    /// @notice Getter for the current initialization version.
    /// @return The current initialization version.
    function initVersion() public view returns (uint8) {
        return INIT_VERSION;
    }
}

// lib/base-contracts/src/libraries/Storage.sol

/// @title Storage
/// @notice Storage handles reading and writing to arbitary storage locations
library Storage {
    /// @notice Returns an address stored in an arbitrary storage slot.
    ///         These storage slots decouple the storage layout from
    ///         solc's automation.
    /// @param _slot The storage slot to retrieve the address from.
    function getAddress(bytes32 _slot) internal view returns (address addr_) {
        assembly {
            addr_ := sload(_slot)
        }
    }

    /// @notice Stores an address in an arbitrary storage slot, `_slot`.
    /// @param _slot The storage slot to store the address in.
    /// @param _address The protocol version to store
    /// @dev WARNING! This function must be used cautiously, as it allows for overwriting addresses
    ///      in arbitrary storage slots.
    function setAddress(bytes32 _slot, address _address) internal {
        assembly {
            sstore(_slot, _address)
        }
    }

    /// @notice Returns a uint256 stored in an arbitrary storage slot.
    ///         These storage slots decouple the storage layout from
    ///         solc's automation.
    /// @param _slot The storage slot to retrieve the address from.
    function getUint(bytes32 _slot) internal view returns (uint256 value_) {
        assembly {
            value_ := sload(_slot)
        }
    }

    /// @notice Stores a value in an arbitrary storage slot, `_slot`.
    /// @param _slot The storage slot to store the address in.
    /// @param _value The protocol version to store
    /// @dev WARNING! This function must be used cautiously, as it allows for overwriting values
    ///      in arbitrary storage slots.
    function setUint(bytes32 _slot, uint256 _value) internal {
        assembly {
            sstore(_slot, _value)
        }
    }

    /// @notice Returns a bytes32 stored in an arbitrary storage slot.
    ///         These storage slots decouple the storage layout from
    ///         solc's automation.
    /// @param _slot The storage slot to retrieve the address from.
    function getBytes32(bytes32 _slot) internal view returns (bytes32 value_) {
        assembly {
            value_ := sload(_slot)
        }
    }

    /// @notice Stores a bytes32 value in an arbitrary storage slot, `_slot`.
    /// @param _slot The storage slot to store the address in.
    /// @param _value The bytes32 value to store.
    /// @dev WARNING! This function must be used cautiously, as it allows for overwriting values
    ///      in arbitrary storage slots.
    function setBytes32(bytes32 _slot, bytes32 _value) internal {
        assembly {
            sstore(_slot, _value)
        }
    }

    /// @notice Stores a bool value in an arbitrary storage slot, `_slot`.
    /// @param _slot The storage slot to store the bool in.
    /// @param _value The bool value to store
    /// @dev WARNING! This function must be used cautiously, as it allows for overwriting values
    ///      in arbitrary storage slots.
    function setBool(bytes32 _slot, bool _value) internal {
        assembly {
            sstore(_slot, _value)
        }
    }

    /// @notice Returns a bool stored in an arbitrary storage slot.
    /// @param _slot The storage slot to retrieve the bool from.
    function getBool(bytes32 _slot) internal view returns (bool value_) {
        assembly {
            value_ := sload(_slot)
        }
    }
}

// lib/base-contracts/src/libraries/Types.sol

/// @title Types
/// @notice Contains various types used throughout the Optimism contract system.
library Types {
    /// @notice OutputProposal represents a commitment to the L2 state. The timestamp is the L1
    ///         timestamp that the output root is posted. This timestamp is used to verify that the
    ///         finalization period has passed since the output root was submitted.
    /// @custom:field outputRoot    Hash of the L2 output.
    /// @custom:field timestamp     Timestamp of the L1 block that the output root was submitted in.
    /// @custom:field l2BlockNumber L2 block number that the output corresponds to.
    struct OutputProposal {
        bytes32 outputRoot;
        uint128 timestamp;
        uint128 l2BlockNumber;
    }

    /// @notice Struct representing the elements that are hashed together to generate an output root
    ///         which itself represents a snapshot of the L2 state.
    /// @custom:field version                  Version of the output root.
    /// @custom:field stateRoot                Root of the state trie at the block of this output.
    /// @custom:field messagePasserStorageRoot Root of the message passer storage trie.
    /// @custom:field latestBlockhash          Hash of the block this output was generated from.
    struct OutputRootProof {
        bytes32 version;
        bytes32 stateRoot;
        bytes32 messagePasserStorageRoot;
        bytes32 latestBlockhash;
    }

    /// @notice Struct representing an output root with a chain id.
    /// @custom:field chainId The chain ID of the L2 chain that the output root commits to.
    /// @custom:field root    The output root.
    struct OutputRootWithChainId {
        uint256 chainId;
        bytes32 root;
    }

    /// @notice Struct representing a super root proof.
    /// @custom:field version     The version of the super root proof.
    /// @custom:field timestamp   The timestamp of the super root proof.
    /// @custom:field outputRoots The output roots that are included in the super root proof.
    struct SuperRootProof {
        bytes1 version;
        uint64 timestamp;
        OutputRootWithChainId[] outputRoots;
    }

    /// @notice Struct representing a deposit transaction (L1 => L2 transaction) created by an end
    ///         user (as opposed to a system deposit transaction generated by the system).
    /// @custom:field from        Address of the sender of the transaction.
    /// @custom:field to          Address of the recipient of the transaction.
    /// @custom:field isCreation  True if the transaction is a contract creation.
    /// @custom:field value       Value to send to the recipient.
    /// @custom:field mint        Amount of ETH to mint.
    /// @custom:field gasLimit    Gas limit of the transaction.
    /// @custom:field data        Data of the transaction.
    /// @custom:field l1BlockHash Hash of the block the transaction was submitted in.
    /// @custom:field logIndex    Index of the log in the block the transaction was submitted in.
    struct UserDepositTransaction {
        address from;
        address to;
        bool isCreation;
        uint256 value;
        uint256 mint;
        uint64 gasLimit;
        bytes data;
        bytes32 l1BlockHash;
        uint256 logIndex;
    }

    /// @notice Struct representing a withdrawal transaction.
    /// @custom:field nonce    Nonce of the withdrawal transaction
    /// @custom:field sender   Address of the sender of the transaction.
    /// @custom:field target   Address of the recipient of the transaction.
    /// @custom:field value    Value to send to the recipient.
    /// @custom:field gasLimit Gas limit of the transaction.
    /// @custom:field data     Data of the transaction.
    struct WithdrawalTransaction {
        uint256 nonce;
        address sender;
        address target;
        uint256 value;
        uint256 gasLimit;
        bytes data;
    }

    /// @notice Enum representing where the FeeVault withdraws funds to.
    /// @custom:value L1 FeeVault withdraws funds to L1.
    /// @custom:value L2 FeeVault withdraws funds to L2.
    enum WithdrawalNetwork {
        L1,
        L2
    }
}

// lib/base-contracts/src/libraries/Constants.sol

// Interfaces

/// @title Constants
/// @notice Constants is a library for storing constants. Simple! Don't put everything in here, just
///         the stuff used in multiple contracts. Constants that only apply to a single contract
///         should be defined in that contract instead.
library Constants {
    /// @notice Special address to be used as the tx origin for gas estimation calls in the
    ///         OptimismPortal and CrossDomainMessenger calls. You only need to use this address if
    ///         the minimum gas limit specified by the user is not actually enough to execute the
    ///         given message and you're attempting to estimate the actual necessary gas limit. We
    ///         use address(1) because it's the ecrecover precompile and therefore guaranteed to
    ///         never have any code on any EVM chain.
    address internal constant ESTIMATION_ADDRESS = address(1);

    /// @notice Value used for the L2 sender storage slot in both the OptimismPortal and the
    ///         CrossDomainMessenger contracts before an actual sender is set. This value is
    ///         non-zero to reduce the gas cost of message passing transactions.
    address internal constant DEFAULT_L2_SENDER = 0x000000000000000000000000000000000000dEaD;

    /// @notice The storage slot that holds the address of a proxy implementation.
    /// @dev `bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)`
    bytes32 internal constant PROXY_IMPLEMENTATION_ADDRESS =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice The storage slot that holds the address of the owner.
    /// @dev `bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1)`
    bytes32 internal constant PROXY_OWNER_ADDRESS = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice The storage slot that holds the guard address in Safe contracts.
    /// @dev `keccak256("guard_manager.guard.address")`
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /// @notice The address that represents ether when dealing with ERC20 token addresses.
    address internal constant ETHER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice The address that represents the system caller responsible for L1 attributes
    ///         transactions.
    address internal constant DEPOSITOR_ACCOUNT = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

    /// @notice Returns the default values for the ResourceConfig. These are the recommended values
    ///         for a production network.
    function DEFAULT_RESOURCE_CONFIG() internal pure returns (IResourceMetering.ResourceConfig memory) {
        IResourceMetering.ResourceConfig memory config = IResourceMetering.ResourceConfig({
            maxResourceLimit: 20_000_000,
            elasticityMultiplier: 10,
            baseFeeMaxChangeDenominator: 8,
            minimumBaseFee: 1 gwei,
            systemTxMaxGas: 1_000_000,
            maximumBaseFee: type(uint128).max
        });
        return config;
    }
}

// lib/base-contracts/interfaces/legacy/IAddressManager.sol

/// @title IAddressManager
/// @notice Interface for the AddressManager contract.
interface IAddressManager is IOwnable {
    event AddressSet(string indexed name, address newAddress, address oldAddress);

    function getAddress(string memory _name) external view returns (address);
    function setAddress(string memory _name, address _address) external;

    function __constructor__() external;
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * `initializer` is equivalent to `reinitializer(1)`, so a reinitializer may be used after the original
     * initialization step. This is essential to configure modules that are added through upgrades and that require
     * initialization.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized < type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }
}

// lib/base-contracts/src/dispute/lib/LibUDT.sol

// Libraries

using LibClaim for Claim global;
using LibHash for Hash global;
using LibDuration for Duration global;
using LibClock for Clock global;
using LibGameId for GameId global;
using LibTimestamp for Timestamp global;
using LibVMStatus for VMStatus global;
using LibGameType for GameType global;

/// @notice A `Clock` represents a packed `Duration` and `Timestamp`
/// @dev The packed layout of this type is as follows:
/// ┌────────────┬────────────────┐
/// │    Bits    │     Value      │
/// ├────────────┼────────────────┤
/// │ [0, 64)    │ Duration       │
/// │ [64, 128)  │ Timestamp      │
/// └────────────┴────────────────┘
type Clock is uint128;

/// @title LibClock
/// @notice This library contains helper functions for working with the `Clock` type.
library LibClock {
    /// @notice Packs a `Duration` and `Timestamp` into a `Clock` type.
    /// @param _duration The `Duration` to pack into the `Clock` type.
    /// @param _timestamp The `Timestamp` to pack into the `Clock` type.
    /// @return clock_ The `Clock` containing the `_duration` and `_timestamp`.
    function wrap(Duration _duration, Timestamp _timestamp) internal pure returns (Clock clock_) {
        assembly {
            clock_ := or(shl(0x40, _duration), _timestamp)
        }
    }

    /// @notice Pull the `Duration` out of a `Clock` type.
    /// @param _clock The `Clock` type to pull the `Duration` out of.
    /// @return duration_ The `Duration` pulled out of `_clock`.
    function duration(Clock _clock) internal pure returns (Duration duration_) {
        // Shift the high-order 64 bits into the low-order 64 bits, leaving only the `duration`.
        assembly {
            duration_ := shr(0x40, _clock)
        }
    }

    /// @notice Pull the `Timestamp` out of a `Clock` type.
    /// @param _clock The `Clock` type to pull the `Timestamp` out of.
    /// @return timestamp_ The `Timestamp` pulled out of `_clock`.
    function timestamp(Clock _clock) internal pure returns (Timestamp timestamp_) {
        // Clean the high-order 192 bits by shifting the clock left and then right again, leaving
        // only the `timestamp`.
        assembly {
            timestamp_ := shr(0xC0, shl(0xC0, _clock))
        }
    }

    /// @notice Get the value of a `Clock` type in the form of the underlying uint128.
    /// @param _clock The `Clock` type to get the value of.
    /// @return clock_ The value of the `Clock` type as a uint128 type.
    function raw(Clock _clock) internal pure returns (uint128 clock_) {
        assembly {
            clock_ := _clock
        }
    }
}

/// @notice A `GameId` represents a packed 4 byte game ID, a 8 byte timestamp, and a 20 byte address.
/// @dev The packed layout of this type is as follows:
/// ┌───────────┬───────────┐
/// │   Bits    │   Value   │
/// ├───────────┼───────────┤
/// │ [0, 32)   │ Game Type │
/// │ [32, 96)  │ Timestamp │
/// │ [96, 256) │ Address   │
/// └───────────┴───────────┘
type GameId is bytes32;

/// @title LibGameId
/// @notice Utility functions for packing and unpacking GameIds.
library LibGameId {
    /// @notice Packs values into a 32 byte GameId type.
    /// @param _gameType The game type.
    /// @param _timestamp The timestamp of the game's creation.
    /// @param _gameProxy The game proxy address.
    /// @return gameId_ The packed GameId.
    function pack(GameType _gameType, Timestamp _timestamp, address _gameProxy) internal pure returns (GameId gameId_) {
        assembly {
            gameId_ := or(or(shl(224, _gameType), shl(160, _timestamp)), _gameProxy)
        }
    }

    /// @notice Unpacks values from a 32 byte GameId type.
    /// @param _gameId The packed GameId.
    /// @return gameType_ The game type.
    /// @return timestamp_ The timestamp of the game's creation.
    /// @return gameProxy_ The game proxy address.
    function unpack(GameId _gameId)
        internal
        pure
        returns (GameType gameType_, Timestamp timestamp_, address gameProxy_)
    {
        assembly {
            gameType_ := shr(224, _gameId)
            timestamp_ := and(shr(160, _gameId), 0xFFFFFFFFFFFFFFFF)
            gameProxy_ := and(_gameId, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }
}

/// @notice A claim represents an MPT root representing the state of the fault proof program.
type Claim is bytes32;

/// @title LibClaim
/// @notice This library contains helper functions for working with the `Claim` type.
library LibClaim {
    /// @notice Get the value of a `Claim` type in the form of the underlying bytes32.
    /// @param _claim The `Claim` type to get the value of.
    /// @return claim_ The value of the `Claim` type as a bytes32 type.
    function raw(Claim _claim) internal pure returns (bytes32 claim_) {
        assembly {
            claim_ := _claim
        }
    }

    /// @notice Hashes a claim and a position together.
    /// @param _claim A Claim type.
    /// @param _position The position of `claim`.
    /// @param _challengeIndex The index of the claim being moved against.
    /// @return claimHash_ A hash of abi.encodePacked(claim, position|challengeIndex);
    function hashClaimPos(
        Claim _claim,
        Position _position,
        uint256 _challengeIndex
    )
        internal
        pure
        returns (Hash claimHash_)
    {
        assembly {
            mstore(0x00, _claim)
            mstore(0x20, or(shl(128, _position), and(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, _challengeIndex)))
            claimHash_ := keccak256(0x00, 0x40)
        }
    }
}

/// @notice A dedicated duration type.
/// @dev Unit: seconds
type Duration is uint64;

/// @title LibDuration
/// @notice This library contains helper functions for working with the `Duration` type.
library LibDuration {
    /// @notice Get the value of a `Duration` type in the form of the underlying uint64.
    /// @param _duration The `Duration` type to get the value of.
    /// @return duration_ The value of the `Duration` type as a uint64 type.
    function raw(Duration _duration) internal pure returns (uint64 duration_) {
        assembly {
            duration_ := _duration
        }
    }
}

/// @notice A custom type for a generic hash.
type Hash is bytes32;

/// @title LibHash
/// @notice This library contains helper functions for working with the `Hash` type.
library LibHash {
    /// @notice Get the value of a `Hash` type in the form of the underlying bytes32.
    /// @param _hash The `Hash` type to get the value of.
    /// @return hash_ The value of the `Hash` type as a bytes32 type.
    function raw(Hash _hash) internal pure returns (bytes32 hash_) {
        assembly {
            hash_ := _hash
        }
    }
}

/// @notice A dedicated timestamp type.
type Timestamp is uint64;

/// @title LibTimestamp
/// @notice This library contains helper functions for working with the `Timestamp` type.
library LibTimestamp {
    /// @notice Get the value of a `Timestamp` type in the form of the underlying uint64.
    /// @param _timestamp The `Timestamp` type to get the value of.
    /// @return timestamp_ The value of the `Timestamp` type as a uint64 type.
    function raw(Timestamp _timestamp) internal pure returns (uint64 timestamp_) {
        assembly {
            timestamp_ := _timestamp
        }
    }
}

/// @notice A `VMStatus` represents the status of a VM execution.
type VMStatus is uint8;

/// @title LibVMStatus
/// @notice This library contains helper functions for working with the `VMStatus` type.
library LibVMStatus {
    /// @notice Get the value of a `VMStatus` type in the form of the underlying uint8.
    /// @param _vmstatus The `VMStatus` type to get the value of.
    /// @return vmstatus_ The value of the `VMStatus` type as a uint8 type.
    function raw(VMStatus _vmstatus) internal pure returns (uint8 vmstatus_) {
        assembly {
            vmstatus_ := _vmstatus
        }
    }
}

/// @notice A `GameType` represents the type of game being played.
type GameType is uint32;

/// @title LibGameType
/// @notice This library contains helper functions for working with the `GameType` type.
library LibGameType {
    /// @notice Get the value of a `GameType` type in the form of the underlying uint32.
    /// @param _gametype The `GameType` type to get the value of.
    /// @return gametype_ The value of the `GameType` type as a uint32 type.
    function raw(GameType _gametype) internal pure returns (uint32 gametype_) {
        assembly {
            gametype_ := _gametype
        }
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

// lib/base-contracts/interfaces/cannon/IPreimageOracle.sol

interface IPreimageOracle {
    struct Leaf {
        bytes input;
        uint256 index;
        bytes32 stateCommitment;
    }

    error ActiveProposal();
    error AlreadyFinalized();
    error AlreadyInitialized();
    error BadProposal();
    error BondTransferFailed();
    error InsufficientBond();
    error InvalidInputSize();
    error InvalidPreimage();
    error InvalidProof();
    error NotEOA();
    error NotInitialized();
    error PartOffsetOOB();
    error PostStateMatches();
    error StatesNotContiguous();
    error TreeSizeOverflow();
    error WrongStartingBlock();

    function KECCAK_TREE_DEPTH() external view returns (uint256);
    function MAX_LEAF_COUNT() external view returns (uint256);
    function MIN_BOND_SIZE() external view returns (uint256);
    function PRECOMPILE_CALL_RESERVED_GAS() external view returns (uint256);
    function addLeavesLPP(
        uint256 _uuid,
        uint256 _inputStartBlock,
        bytes memory _input,
        bytes32[] memory _stateCommitments,
        bool _finalize
    )
        external;
    function challengeFirstLPP(
        address _claimant,
        uint256 _uuid,
        Leaf memory _postState,
        bytes32[] memory _postStateProof
    )
        external;
    function challengeLPP(
        address _claimant,
        uint256 _uuid,
        LibKeccak.StateMatrix memory _stateMatrix,
        Leaf memory _preState,
        bytes32[] memory _preStateProof,
        Leaf memory _postState,
        bytes32[] memory _postStateProof
    )
        external;
    function challengePeriod() external view returns (uint256 challengePeriod_);
    function getTreeRootLPP(address _owner, uint256 _uuid) external view returns (bytes32 treeRoot_);
    function initLPP(uint256 _uuid, uint32 _partOffset, uint32 _claimedSize) external payable;
    function loadBlobPreimagePart(
        uint256 _z,
        uint256 _y,
        bytes memory _commitment,
        bytes memory _proof,
        uint256 _partOffset
    )
        external;
    function loadKeccak256PreimagePart(uint256 _partOffset, bytes memory _preimage) external;
    function loadLocalData(
        uint256 _ident,
        bytes32 _localContext,
        bytes32 _word,
        uint256 _size,
        uint256 _partOffset
    )
        external
        returns (bytes32 key_);
    function loadPrecompilePreimagePart(
        uint256 _partOffset,
        address _precompile,
        uint64 _requiredGas,
        bytes memory _input
    )
        external;
    function loadSha256PreimagePart(uint256 _partOffset, bytes memory _preimage) external;
    function minProposalSize() external view returns (uint256 minProposalSize_);
    function preimageLengths(bytes32) external view returns (uint256);
    function preimagePartOk(bytes32, uint256) external view returns (bool);
    function preimageParts(bytes32, uint256) external view returns (bytes32);
    function proposalBlocks(address, uint256, uint256) external view returns (uint64);
    function proposalBlocksLen(address _claimant, uint256 _uuid) external view returns (uint256 len_);
    function proposalBonds(address, uint256) external view returns (uint256);
    function proposalBranches(address, uint256, uint256) external view returns (bytes32);
    function proposalCount() external view returns (uint256 count_);
    function proposalMetadata(address, uint256) external view returns (LPPMetaData);
    function proposalParts(address, uint256) external view returns (bytes32);
    function proposals(uint256) external view returns (address claimant, uint256 uuid); // nosemgrep:
        // sol-style-return-arg-fmt
    function readPreimage(bytes32 _key, uint256 _offset) external view returns (bytes32 dat_, uint256 datLen_);
    function squeezeLPP(
        address _claimant,
        uint256 _uuid,
        LibKeccak.StateMatrix memory _stateMatrix,
        Leaf memory _preState,
        bytes32[] memory _preStateProof,
        Leaf memory _postState,
        bytes32[] memory _postStateProof
    )
        external;
    function version() external view returns (string memory);
    function zeroHashes(uint256) external view returns (bytes32);

    function __constructor__(uint256 _minProposalSize, uint256 _challengePeriod) external;
}

// lib/base-contracts/interfaces/universal/IProxyAdmin.sol

interface IProxyAdmin {
    enum ProxyType {
        ERC1967,
        CHUGSPLASH,
        RESOLVED
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function addressManager() external view returns (IAddressManager);
    function changeProxyAdmin(address payable _proxy, address _newAdmin) external;
    function getProxyAdmin(address payable _proxy) external view returns (address);
    function getProxyImplementation(address _proxy) external view returns (address);
    function implementationName(address) external view returns (string memory);
    function isUpgrading() external view returns (bool);
    function owner() external view returns (address);
    function proxyType(address) external view returns (ProxyType);
    function renounceOwnership() external;
    function setAddress(string memory _name, address _address) external;
    function setAddressManager(IAddressManager _address) external;
    function setImplementationName(address _address, string memory _name) external;
    function setProxyType(address _address, ProxyType _type) external;
    function setUpgrading(bool _upgrading) external;
    function transferOwnership(address newOwner) external; // nosemgrep
    function upgrade(address payable _proxy, address _implementation) external;
    function upgradeAndCall(address payable _proxy, address _implementation, bytes memory _data) external payable;

    function __constructor__(address _owner) external;
}

// lib/base-contracts/src/dispute/lib/Types.sol

// Libraries

/// @notice The current status of the dispute game.
enum GameStatus {
    // The game is currently in progress, and has not been resolved.
    IN_PROGRESS,
    // The game has concluded, and the `rootClaim` was challenged successfully.
    CHALLENGER_WINS,
    // The game has concluded, and the `rootClaim` could not be contested.
    DEFENDER_WINS
}

/// @notice The game's bond distribution type. Games are expected to start in the `UNDECIDED`
///         state, and then choose either `NORMAL` or `REFUND`.
enum BondDistributionMode {
    // Bond distribution strategy has not been chosen.
    UNDECIDED,
    // Bonds should be distributed as normal.
    NORMAL,
    // Bonds should be refunded to claimants.
    REFUND
}

/// @notice Represents an L2 root and the L2 sequence number at which it was generated.
/// @custom:field root The output root.
/// @custom:field l2SequenceNumber The L2 Sequence Number ( e.g. block number / timestamp) at which the root was
/// generated.
struct Proposal {
    Hash root;
    uint256 l2SequenceNumber;
}

/// @title GameTypes
/// @notice A library that defines the IDs of games that can be played.
library GameTypes {
    /// @dev A dispute game type the uses the cannon vm.
    GameType internal constant CANNON = GameType.wrap(0);

    /// @dev A permissioned dispute game type that uses the cannon vm.
    GameType internal constant PERMISSIONED_CANNON = GameType.wrap(1);

    /// @notice A dispute game type that uses the asterisc vm.
    GameType internal constant ASTERISC = GameType.wrap(2);

    /// @notice A dispute game type that uses the asterisc vm with Kona.
    GameType internal constant ASTERISC_KONA = GameType.wrap(3);

    /// @notice A dispute game type that uses the cannon vm (Super Roots).
    GameType internal constant SUPER_CANNON = GameType.wrap(4);

    /// @notice A dispute game type that uses the permissioned cannon vm (Super Roots).
    GameType internal constant SUPER_PERMISSIONED_CANNON = GameType.wrap(5);

    /// @notice A dispute game type that uses OP Succinct
    GameType internal constant OP_SUCCINCT = GameType.wrap(6);

    /// @notice A dispute game type that uses the asterisc vm with Kona (Super Roots).
    GameType internal constant SUPER_ASTERISC_KONA = GameType.wrap(7);

    /// @notice A dispute game type that uses the cannon vm with Kona.
    GameType internal constant CANNON_KONA = GameType.wrap(8);

    /// @notice A dispute game type that uses the cannon vm with Kona (Super Roots).
    GameType internal constant SUPER_CANNON_KONA = GameType.wrap(9);

    /// @notice A dispute game type with short game duration for testing withdrawals.
    ///         Not intended for production use.
    GameType internal constant FAST = GameType.wrap(254);

    /// @notice A dispute game type that uses an alphabet vm.
    ///         Not intended for production use.
    GameType internal constant ALPHABET = GameType.wrap(255);

    /// @notice A dispute game type that uses RISC Zero's Kailua
    GameType internal constant KAILUA = GameType.wrap(1337);
}

/// @title VMStatuses
/// @notice Named type aliases for the various valid VM status bytes.
library VMStatuses {
    /// @notice The VM has executed successfully and the outcome is valid.
    VMStatus internal constant VALID = VMStatus.wrap(0);

    /// @notice The VM has executed successfully and the outcome is invalid.
    VMStatus internal constant INVALID = VMStatus.wrap(1);

    /// @notice The VM has paniced.
    VMStatus internal constant PANIC = VMStatus.wrap(2);

    /// @notice The VM execution is still in progress.
    VMStatus internal constant UNFINISHED = VMStatus.wrap(3);
}

/// @title LocalPreimageKey
/// @notice Named type aliases for local `PreimageOracle` key identifiers.
library LocalPreimageKey {
    /// @notice The identifier for the L1 head hash.
    uint256 internal constant L1_HEAD_HASH = 0x01;

    /// @notice The identifier for the starting output root.
    uint256 internal constant STARTING_OUTPUT_ROOT = 0x02;

    /// @notice The identifier for the disputed output root.
    uint256 internal constant DISPUTED_OUTPUT_ROOT = 0x03;

    /// @notice The identifier for the disputed L2 block number.
    uint256 internal constant DISPUTED_L2_BLOCK_NUMBER = 0x04;

    /// @notice The identifier for the chain ID.
    uint256 internal constant CHAIN_ID = 0x05;
}

////////////////////////////////////////////////////////////////
//            `OPSuccinctFaultDisputeGame` Types             //
////////////////////////////////////////////////////////////////

uint32 constant OP_SUCCINCT_FAULT_DISPUTE_GAME_TYPE = 42;

/// @notice The public values committed to for an OP Succinct aggregation program.
struct AggregationOutputs {
    bytes32 l1Head;
    bytes32 l2PreRoot;
    bytes32 claimRoot;
    uint256 claimBlockNum;
    bytes32 rollupConfigHash;
    bytes32 rangeVkeyCommitment;
    address proverAddress;
}

// lib/base-contracts/interfaces/dispute/IBigStepper.sol

/// @title IBigStepper
/// @notice Describes a state machine that can perform a single instruction step, provided a prestate and an optional
///         proof.
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣼⠶⢅⠒⢄⢔⣶⡦⣤⡤⠄⣀⠀⠀⠀⠀⠀⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠨⡏⠀⠀⠈⠢⣙⢯⣄⠀⢨⠯⡺⡘⢄⠀⠀⠀⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣶⡆⠀⠀⠀⠀⠈⠓⠬⡒⠡⣀⢙⡜⡀⠓⠄⠀⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡷⠿⣧⣀⡀⠀⠀⠀⠀⠀⠀⠉⠣⣞⠩⠥⠀⠼⢄⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⠀⠀⠀⠉⢹⣶⠒⠒⠂⠈⠉⠁⠘⡆⠀⣿⣿⠫⡄⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⢶⣤⣀⡀⠀⠀⢸⡿⠀⠀⠀⠀⠀⢀⠞⠀⠀⢡⢨⢀⡄⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⡒⣿⢿⡤⠝⡣⠉⠁⠚⠛⠀⠤⠤⣄⡰⠁⠀⠀⠀⠉⠙⢸⠀⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡤⢯⡌⡿⡇⠘⡷⠀⠁⠀⠀⢀⣰⠢⠲⠛⣈⣸⠦⠤⠶⠴⢬⣐⣊⡂⠀
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⡪⡗⢫⠞⠀⠆⣀⠻⠤⠴⠐⠚⣉⢀⠦⠂⠋⠁⠀⠁⠀⠀⠀⠀⢋⠉⠇⠀
/// ⠀⠀⠀⠀⣀⡤⠐⠒⠘⡹⠉⢸⠇⠸⠀⠀⠀⠀⣀⣤⠴⠚⠉⠈⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠼⠀⣾⠀
/// ⠀⠀⠀⡰⠀⠉⠉⠀⠁⠀⠀⠈⢇⠈⠒⠒⠘⠈⢀⢡⡂⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⠀⢸⡄
/// ⠀⠀⠸⣿⣆⠤⢀⡀⠀⠀⠀⠀⢘⡌⠀⠀⣀⣀⣀⡈⣤⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⢸⡇
/// ⠀⠀⢸⣀⠀⠉⠒⠐⠛⠋⠭⠭⠍⠉⠛⠒⠒⠒⠀⠒⠚⠛⠛⠛⠩⠭⠭⠭⠭⠤⠤⠤⠤⠤⠭⠭⠉⠓⡆
/// ⠀⠀⠘⠿⣷⣶⣤⣤⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣤⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇
/// ⠀⠀⠀⠀⠀⠉⠙⠛⠛⠻⠿⢿⣿⣿⣷⣶⣶⣶⣤⣤⣀⣁⣛⣃⣒⠿⠿⠿⠤⠠⠄⠤⠤⢤⣛⣓⣂⣻⡇
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠉⠉⠉⠙⠛⠻⠿⠿⠿⢿⣿⣿⣿⣷⣶⣶⣾⣿⣿⣿⣿⠿⠟⠁
/// ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠈⠉⠉⠉⠉⠁⠀⠀⠀⠀⠀
interface IBigStepper {
    /// @notice Performs the state transition from a given prestate and returns the hash of the post state witness.
    /// @param _stateData The raw opaque prestate data.
    /// @param _proof Opaque proof data, can be used to prove things about the prestate in relation to the state of the
    ///               interface's implementation.
    /// @param _localContext The local key context for the preimage oracle. Optional, can be set as a constant if the
    ///                      implementation only requires one set of local keys.
    /// @return postState_ The hash of the post state witness after the state transition.
    function step(
        bytes calldata _stateData,
        bytes calldata _proof,
        bytes32 _localContext
    )
        external
        returns (bytes32 postState_);

    /// @notice Returns the preimage oracle used by the state machine.
    function oracle() external view returns (IPreimageOracle oracle_);
}

// lib/base-contracts/interfaces/L1/IProxyAdminOwnedBase.sol

interface IProxyAdminOwnedBase {
    error ProxyAdminOwnedBase_NotSharedProxyAdminOwner();
    error ProxyAdminOwnedBase_NotProxyAdminOwner();
    error ProxyAdminOwnedBase_NotProxyAdmin();
    error ProxyAdminOwnedBase_NotProxyAdminOrProxyAdminOwner();
    error ProxyAdminOwnedBase_ProxyAdminNotFound();
    error ProxyAdminOwnedBase_NotResolvedDelegateProxy();

    function proxyAdmin() external view returns (IProxyAdmin);
    function proxyAdminOwner() external view returns (address);
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}

// lib/base-contracts/interfaces/dispute/IDisputeGame.sol

interface IDisputeGame is IInitializable {
    event Resolved(GameStatus indexed status);

    function createdAt() external view returns (Timestamp);
    function resolvedAt() external view returns (Timestamp);
    function status() external view returns (GameStatus);
    function gameType() external view returns (GameType gameType_);
    function gameCreator() external pure returns (address creator_);
    function rootClaim() external pure returns (Claim rootClaim_);
    function l1Head() external pure returns (Hash l1Head_);
    function l2SequenceNumber() external pure returns (uint256 l2SequenceNumber_);
    function extraData() external pure returns (bytes memory extraData_);
    function resolve() external returns (GameStatus status_);
    function gameData() external view returns (GameType gameType_, Claim rootClaim_, bytes memory extraData_);
    function wasRespectedGameTypeWhenCreated() external view returns (bool);
}

// lib/base-contracts/interfaces/L1/ISuperchainConfig.sol

interface ISuperchainConfig is IProxyAdminOwnedBase {
    event Paused(address identifier);
    event Unpaused(address identifier);
    event PauseExtended(address identifier);

    error SuperchainConfig_OnlyGuardian();
    error SuperchainConfig_OnlyGuardianOrIncidentResponder();
    error SuperchainConfig_AlreadyPaused(address identifier);
    error SuperchainConfig_NotAlreadyPaused(address identifier);

    function guardian() external view returns (address);
    function incidentResponder() external view returns (address);
    function pause(address _identifier) external;
    function unpause(address _identifier) external;
    function pausable(address _identifier) external view returns (bool);
    function paused() external view returns (bool);
    function paused(address _identifier) external view returns (bool);
    function expiration(address _identifier) external view returns (uint256);
    function extend(address _identifier) external;
    function version() external view returns (string memory);
    function pauseTimestamps(address) external view returns (uint256);
    function pauseExpiry() external view returns (uint256);

    function __constructor__(address _guardian, address _incidentResponder) external;
}

// lib/base-contracts/interfaces/L1/ISystemConfig.sol

interface ISystemConfig is IProxyAdminOwnedBase {
    enum UpdateType {
        BATCHER,
        FEE_SCALARS,
        GAS_LIMIT,
        UNSAFE_BLOCK_SIGNER,
        EIP_1559_PARAMS,
        OPERATOR_FEE_PARAMS,
        MIN_BASE_FEE,
        DA_FOOTPRINT_GAS_SCALAR
    }

    struct Addresses {
        address l1CrossDomainMessenger;
        address l1ERC721Bridge;
        address l1StandardBridge;
        address optimismPortal;
        address optimismMintableERC20Factory;
        address delayedWETH;
    }

    error ReinitializableBase_ZeroInitVersion();
    error SystemConfig_InvalidFeatureState();

    event ConfigUpdate(uint256 indexed version, UpdateType indexed updateType, bytes data);
    event FeatureSet(bytes32 indexed feature, bool indexed enabled);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function BATCH_INBOX_SLOT() external view returns (bytes32);
    function L1_CROSS_DOMAIN_MESSENGER_SLOT() external view returns (bytes32);
    function L1_ERC_721_BRIDGE_SLOT() external view returns (bytes32);
    function L1_STANDARD_BRIDGE_SLOT() external view returns (bytes32);
    function OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT() external view returns (bytes32);
    function OPTIMISM_PORTAL_SLOT() external view returns (bytes32);
    function DELAYED_WETH_SLOT() external view returns (bytes32);
    function START_BLOCK_SLOT() external view returns (bytes32);
    function UNSAFE_BLOCK_SIGNER_SLOT() external view returns (bytes32);
    function VERSION() external view returns (uint256);
    function basefeeScalar() external view returns (uint32);
    function batchInbox() external view returns (address addr_);
    function batcherHash() external view returns (bytes32);
    function blobbasefeeScalar() external view returns (uint32);
    function disputeGameFactory() external view returns (address addr_);
    function gasLimit() external view returns (uint64);
    function eip1559Denominator() external view returns (uint32);
    function eip1559Elasticity() external view returns (uint32);
    function getAddresses() external view returns (Addresses memory);
    function initialize(
        address _owner,
        uint32 _basefeeScalar,
        uint32 _blobbasefeeScalar,
        bytes32 _batcherHash,
        uint64 _gasLimit,
        address _unsafeBlockSigner,
        IResourceMetering.ResourceConfig memory _config,
        address _batchInbox,
        Addresses memory _addresses,
        uint256 _l2ChainId,
        ISuperchainConfig _superchainConfig
    )
        external;
    function initVersion() external view returns (uint8);
    function l1CrossDomainMessenger() external view returns (address addr_);
    function l1ERC721Bridge() external view returns (address addr_);
    function l1StandardBridge() external view returns (address addr_);
    function l2ChainId() external view returns (uint256);
    function maximumGasLimit() external pure returns (uint64);
    function minimumGasLimit() external view returns (uint64);
    function operatorFeeConstant() external view returns (uint64);
    function operatorFeeScalar() external view returns (uint32);
    function minBaseFee() external view returns (uint64);
    function daFootprintGasScalar() external view returns (uint16);
    function optimismMintableERC20Factory() external view returns (address addr_);
    function optimismPortal() external view returns (address addr_);
    function delayedWETH() external view returns (address addr_);
    function overhead() external view returns (uint256);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function resourceConfig() external view returns (IResourceMetering.ResourceConfig memory);
    function scalar() external view returns (uint256);
    function setBatcherHash(address _batcher) external;
    function setBatcherHash(bytes32 _batcherHash) external;
    function setGasConfig(uint256 _overhead, uint256 _scalar) external;
    function setGasConfigEcotone(uint32 _basefeeScalar, uint32 _blobbasefeeScalar) external;
    function setGasLimit(uint64 _gasLimit) external;
    function setOperatorFeeScalars(uint32 _operatorFeeScalar, uint64 _operatorFeeConstant) external;
    function setUnsafeBlockSigner(address _unsafeBlockSigner) external;
    function setEIP1559Params(uint32 _denominator, uint32 _elasticity) external;
    function setMinBaseFee(uint64 _minBaseFee) external;
    function setDAFootprintGasScalar(uint16 _daFootprintGasScalar) external;
    function startBlock() external view returns (uint256 startBlock_);
    function transferOwnership(address newOwner) external; // nosemgrep
    function unsafeBlockSigner() external view returns (address addr_);
    function version() external pure returns (string memory);
    function paused() external view returns (bool);
    function superchainConfig() external view returns (ISuperchainConfig);
    function guardian() external view returns (address);
    function setFeature(bytes32 _feature, bool _enabled) external;
    function isFeatureEnabled(bytes32) external view returns (bool);
    function isCustomGasToken() external view returns (bool);

    function __constructor__() external;
}

// lib/base-contracts/src/L1/ProxyAdminOwnedBase.sol

// Libraries

// Interfaces

/// @notice Base contract for ProxyAdmin-owned contracts. This contract is used to introspect
///         compatible Proxy contracts so that their ProxyAdmin and ProxyAdmin owner addresses can
///         be retrieved onchain. Existing Proxy contracts don't have these getters, so we need a
///         base contract instead.
/// @dev WARNING: This contract is ONLY designed to be used with either the Optimism Proxy
///      implementation or the Optimism ResolvedDelegateProxy implementation. It is not safe to use
///      this contract with any other proxy implementation.
///      WARNING: Multiple OP Stack chains may share the same ProxyAdmin owner address.
abstract contract ProxyAdminOwnedBase {
    /// @notice Thrown when the ProxyAdmin owner of the current contract is not the same as the
    ///         ProxyAdmin owner of the other Proxy address provided.
    error ProxyAdminOwnedBase_NotSharedProxyAdminOwner();

    /// @notice Thrown when the caller is not the ProxyAdmin owner.
    error ProxyAdminOwnedBase_NotProxyAdminOwner();

    /// @notice Thrown when the caller is not the ProxyAdmin.
    error ProxyAdminOwnedBase_NotProxyAdmin();

    /// @notice Thrown when the caller is not the ProxyAdmin owner or the ProxyAdmin.
    error ProxyAdminOwnedBase_NotProxyAdminOrProxyAdminOwner();

    /// @notice Thrown when the ProxyAdmin owner of the current contract is not found.
    error ProxyAdminOwnedBase_ProxyAdminNotFound();

    /// @notice Thrown when the current contract is not a ResolvedDelegateProxy.
    error ProxyAdminOwnedBase_NotResolvedDelegateProxy();

    /// @notice Getter for the owner of the ProxyAdmin.
    function proxyAdminOwner() public view returns (address) {
        return proxyAdmin().owner();
    }

    /// @notice Getter for the ProxyAdmin contract that owns this Proxy contract.
    function proxyAdmin() public view returns (IProxyAdmin) {
        // First check for a non-zero address in the reserved slot.
        address proxyAdminAddress = Storage.getAddress(Constants.PROXY_OWNER_ADDRESS);
        if (proxyAdminAddress != address(0)) {
            return IProxyAdmin(proxyAdminAddress);
        }

        // Otherwise, we'll try to read the AddressManager slot.
        // First we make sure this is almost certainly a ResolvedDelegateProxy. We only have a
        // single ResolvedDelegateProxy and it's for the L1CrossDomainMessenger, so we'll check
        // that the storage slot for the mapping at slot 0 returns the string
        // "OVM_L1CrossDomainMessenger". We need to use Solidity's rules for how strings are stored
        // in storage slots to do this.
        if (
            Storage.getBytes32(keccak256(abi.encode(address(this), uint256(0))))
                != bytes32(
                    uint256(bytes32("OVM_L1CrossDomainMessenger"))
                        | uint256(bytes("OVM_L1CrossDomainMessenger").length * 2)
                )
        ) {
            revert ProxyAdminOwnedBase_NotResolvedDelegateProxy();
        }

        // Ok, now we'll try to read the AddressManager slot.
        address addressManagerAddress = Storage.getAddress(keccak256(abi.encode(address(this), uint256(1))));
        if (addressManagerAddress != address(0)) {
            return IProxyAdmin(IAddressManager(addressManagerAddress).owner());
        }

        // We should revert here, we couldn't find a non-zero owner address.
        revert ProxyAdminOwnedBase_ProxyAdminNotFound();
    }

    /// @notice Reverts if the ProxyAdmin owner of the current contract is not the same as the
    ///         ProxyAdmin owner of the other Proxy address provided. Useful asserting that both
    ///         the current contract and the other Proxy share the same security model.+
    function _assertSharedProxyAdminOwner(address _proxy) internal view {
        if (proxyAdminOwner() != ProxyAdminOwnedBase(_proxy).proxyAdminOwner()) {
            revert ProxyAdminOwnedBase_NotSharedProxyAdminOwner();
        }
    }

    /// @notice Reverts if the caller is not the ProxyAdmin owner.
    function _assertOnlyProxyAdminOwner() internal view {
        if (proxyAdminOwner() != msg.sender) {
            revert ProxyAdminOwnedBase_NotProxyAdminOwner();
        }
    }

    /// @notice Reverts if the caller is not the ProxyAdmin.
    function _assertOnlyProxyAdmin() internal view {
        if (address(proxyAdmin()) != msg.sender) {
            revert ProxyAdminOwnedBase_NotProxyAdmin();
        }
    }

    function _assertOnlyProxyAdminOrProxyAdminOwner() internal view {
        if (address(proxyAdmin()) != msg.sender && proxyAdminOwner() != msg.sender) {
            revert ProxyAdminOwnedBase_NotProxyAdminOrProxyAdminOwner();
        }
    }
}

// lib/base-contracts/interfaces/dispute/IDelayedWETH.sol

interface IDelayedWETH is IProxyAdminOwnedBase {
    error ReinitializableBase_ZeroInitVersion();

    struct WithdrawalRequest {
        uint256 amount;
        uint256 timestamp;
    }

    event Initialized(uint8 version);

    fallback() external payable;
    receive() external payable;

    function initVersion() external view returns (uint8);
    function systemConfig() external view returns (ISystemConfig);
    function delay() external view returns (uint256);
    function hold(address _guy) external;
    function hold(address _guy, uint256 _wad) external;
    function initialize(ISystemConfig _systemConfig) external;
    function recover(uint256 _wad) external;
    function unlock(address _guy, uint256 _wad) external;
    function withdraw(address _guy, uint256 _wad) external;
    function withdrawals(address, address) external view returns (uint256 amount, uint256 timestamp);
    function version() external view returns (string memory);
    function withdraw(uint256 _wad) external;

    event Approval(address indexed src, address indexed guy, uint256 wad);

    event Transfer(address indexed src, address indexed dst, uint256 wad);

    event Deposit(address indexed dst, uint256 wad);

    event Withdrawal(address indexed src, uint256 wad);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address src) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function deposit() external payable;

    function totalSupply() external view returns (uint256);

    function approve(address guy, uint256 wad) external returns (bool);

    function transfer(address dst, uint256 wad) external returns (bool);

    function transferFrom(address src, address dst, uint256 wad) external returns (bool);

    function config() external view returns (ISuperchainConfig);

    function __constructor__(uint256 _delay) external;
}

// lib/base-contracts/interfaces/dispute/IDisputeGameFactory.sol

interface IDisputeGameFactory is IProxyAdminOwnedBase, IReinitializableBase {
    struct GameSearchResult {
        uint256 index;
        GameId metadata;
        Timestamp timestamp;
        Claim rootClaim;
        bytes extraData;
    }

    error GameAlreadyExists(Hash uuid);
    error IncorrectBondAmount();
    error NoImplementation(GameType gameType);

    event DisputeGameCreated(address indexed disputeProxy, GameType indexed gameType, Claim indexed rootClaim);
    event ImplementationSet(address indexed impl, GameType indexed gameType);
    event ImplementationArgsSet(GameType indexed gameType, bytes args);
    event InitBondUpdated(GameType indexed gameType, uint256 indexed newBond);
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function create(
        GameType _gameType,
        Claim _rootClaim,
        bytes memory _extraData
    )
        external
        payable
        returns (IDisputeGame proxy_);
    function findLatestGames(
        GameType _gameType,
        uint256 _start,
        uint256 _n
    )
        external
        view
        returns (GameSearchResult[] memory games_);
    function gameAtIndex(uint256 _index)
        external
        view
        returns (GameType gameType_, Timestamp timestamp_, IDisputeGame proxy_);
    function gameCount() external view returns (uint256 gameCount_);
    function gameArgs(GameType) external view returns (bytes memory);
    function gameImpls(GameType) external view returns (IDisputeGame);
    function games(
        GameType _gameType,
        Claim _rootClaim,
        bytes memory _extraData
    )
        external
        view
        returns (IDisputeGame proxy_, Timestamp timestamp_);
    function getGameUUID(
        GameType _gameType,
        Claim _rootClaim,
        bytes memory _extraData
    )
        external
        pure
        returns (Hash uuid_);
    function initBonds(GameType) external view returns (uint256);
    function initialize(address _owner) external;
    function owner() external view returns (address);
    function renounceOwnership() external;
    function setImplementation(GameType _gameType, IDisputeGame _impl) external;
    function setImplementation(GameType _gameType, IDisputeGame _impl, bytes calldata _args) external;
    function setInitBond(GameType _gameType, uint256 _initBond) external;
    function transferOwnership(address newOwner) external; // nosemgrep
    function version() external view returns (string memory);

    function __constructor__() external;
}

// lib/base-contracts/interfaces/dispute/IAnchorStateRegistry.sol

interface IAnchorStateRegistry is IProxyAdminOwnedBase {
    error AnchorStateRegistry_InvalidAnchorGame();
    error AnchorStateRegistry_Unauthorized();
    error ReinitializableBase_ZeroInitVersion();

    event AnchorUpdated(IFaultDisputeGame indexed game);
    event DisputeGameBlacklisted(IDisputeGame indexed disputeGame);
    event Initialized(uint8 version);
    event RespectedGameTypeSet(GameType gameType);
    event RetirementTimestampSet(uint256 timestamp);

    function initVersion() external view returns (uint8);
    function anchorGame() external view returns (IFaultDisputeGame);
    function anchors(GameType) external view returns (Hash, uint256);
    function blacklistDisputeGame(IDisputeGame _disputeGame) external;
    function disputeGameBlacklist(IDisputeGame) external view returns (bool);
    function getAnchorRoot() external view returns (Hash, uint256);
    function getStartingAnchorRoot() external view returns (Proposal memory);
    function disputeGameFinalityDelaySeconds() external view returns (uint256);
    function disputeGameFactory() external view returns (IDisputeGameFactory);
    function initialize(
        ISystemConfig _systemConfig,
        IDisputeGameFactory _disputeGameFactory,
        Proposal memory _startingAnchorRoot,
        GameType _startingRespectedGameType
    )
        external;
    function isGameBlacklisted(IDisputeGame _game) external view returns (bool);
    function isGameProper(IDisputeGame _game) external view returns (bool);
    function isGameRegistered(IDisputeGame _game) external view returns (bool);
    function isGameResolved(IDisputeGame _game) external view returns (bool);
    function isGameRespected(IDisputeGame _game) external view returns (bool);
    function isGameRetired(IDisputeGame _game) external view returns (bool);
    function isGameFinalized(IDisputeGame _game) external view returns (bool);
    function isGameClaimValid(IDisputeGame _game) external view returns (bool);
    function paused() external view returns (bool);
    function respectedGameType() external view returns (GameType);
    function retirementTimestamp() external view returns (uint64);
    function setAnchorState(IDisputeGame _game) external;
    function setRespectedGameType(GameType _gameType) external;
    function systemConfig() external view returns (ISystemConfig);
    function updateRetirementTimestamp() external;
    function version() external view returns (string memory);
    function superchainConfig() external view returns (ISuperchainConfig);

    function __constructor__(
        uint256 _disputeGameFinalityDelaySeconds
    ) external;
}

// lib/base-contracts/interfaces/dispute/IFaultDisputeGame.sol

interface IFaultDisputeGame is IDisputeGame {
    struct ClaimData {
        uint32 parentIndex;
        address counteredBy;
        address claimant;
        uint128 bond;
        Claim claim;
        Position position;
        Clock clock;
    }

    struct ResolutionCheckpoint {
        bool initialCheckpointComplete;
        uint32 subgameIndex;
        Position leftmostPosition;
        address counteredBy;
    }

    struct GameConstructorParams {
        GameType gameType;
        Claim absolutePrestate;
        uint256 maxGameDepth;
        uint256 splitDepth;
        Duration clockExtension;
        Duration maxClockDuration;
        IBigStepper vm;
        IDelayedWETH weth;
        IAnchorStateRegistry anchorStateRegistry;
        uint256 l2ChainId;
    }

    error AlreadyInitialized();
    error AnchorRootNotFound();
    error BadExtraData();
    error BlockNumberMatches();
    error BondTransferFailed();
    error CannotDefendRootClaim();
    error ClaimAboveSplit();
    error ClaimAlreadyExists();
    error ClaimAlreadyResolved();
    error ClockNotExpired();
    error ClockTimeExceeded();
    error ContentLengthMismatch();
    error DuplicateStep();
    error EmptyItem();
    error GameDepthExceeded();
    error GameNotInProgress();
    error IncorrectBondAmount();
    error InvalidChallengePeriod();
    error InvalidClockExtension();
    error InvalidDataRemainder();
    error InvalidDisputedClaimIndex();
    error InvalidHeader();
    error InvalidHeaderRLP();
    error InvalidLocalIdent();
    error InvalidOutputRootProof();
    error InvalidParent();
    error InvalidPrestate();
    error InvalidSplitDepth();
    error L2BlockNumberChallenged();
    error MaxDepthTooLarge();
    error NoCreditToClaim();
    error OutOfOrderResolution();
    error UnexpectedList();
    error UnexpectedRootClaim(Claim rootClaim);
    error UnexpectedString();
    error ValidStep();
    error InvalidBondDistributionMode();
    error GameNotFinalized();
    error GameNotResolved();
    error ReservedGameType();
    error GamePaused();
    event Move(uint256 indexed parentIndex, Claim indexed claim, address indexed claimant);
    event GameClosed(BondDistributionMode bondDistributionMode);

    function absolutePrestate() external view returns (Claim absolutePrestate_);
    function addLocalData(uint256 _ident, uint256 _execLeafIdx, uint256 _partOffset) external;
    function anchorStateRegistry() external view returns (IAnchorStateRegistry registry_);
    function attack(Claim _disputed, uint256 _parentIndex, Claim _claim) external payable;
    function bondDistributionMode() external view returns (BondDistributionMode);
    function challengeRootL2Block(Types.OutputRootProof memory _outputRootProof, bytes memory _headerRLP) external;
    function claimCredit(address _recipient) external;
    function claimData(uint256)
        external
        view // nosemgrep
        returns (
            uint32 parentIndex,
            address counteredBy,
            address claimant,
            uint128 bond,
            Claim claim,
            Position position,
            Clock clock
        );
    function claimDataLen() external view returns (uint256 len_);
    function claims(Hash) external view returns (bool);
    function clockExtension() external view returns (Duration clockExtension_);
    function closeGame() external;
    function credit(address _recipient) external view returns (uint256 credit_);
    function defend(Claim _disputed, uint256 _parentIndex, Claim _claim) external payable;
    function getChallengerDuration(uint256 _claimIndex) external view returns (Duration duration_);
    function getNumToResolve(uint256 _claimIndex) external view returns (uint256 numRemainingChildren_);
    function getRequiredBond(Position _position) external view returns (uint256 requiredBond_);
    function hasUnlockedCredit(address) external view returns (bool);
    function l2BlockNumber() external pure returns (uint256 l2BlockNumber_);
    function l2BlockNumberChallenged() external view returns (bool);
    function l2BlockNumberChallenger() external view returns (address);
    function l2ChainId() external view returns (uint256 l2ChainId_);
    function maxClockDuration() external view returns (Duration maxClockDuration_);
    function maxGameDepth() external view returns (uint256 maxGameDepth_);
    function move(Claim _disputed, uint256 _challengeIndex, Claim _claim, bool _isAttack) external payable;
    function normalModeCredit(address) external view returns (uint256);
    function refundModeCredit(address) external view returns (uint256);
    function resolutionCheckpoints(uint256)
        external
        view
        returns (bool initialCheckpointComplete, uint32 subgameIndex, Position leftmostPosition, address counteredBy); // nosemgrep
    function resolveClaim(uint256 _claimIndex, uint256 _numToResolve) external;
    function resolvedSubgames(uint256) external view returns (bool);
    function splitDepth() external view returns (uint256 splitDepth_);
    function startingBlockNumber() external view returns (uint256 startingBlockNumber_);
    function startingOutputRoot() external view returns (Hash root, uint256 l2SequenceNumber); // nosemgrep
    function startingRootHash() external view returns (Hash startingRootHash_);
    function step(uint256 _claimIndex, bool _isAttack, bytes memory _stateData, bytes memory _proof) external;
    function subgames(uint256, uint256) external view returns (uint256);
    function version() external pure returns (string memory);
    function vm() external view returns (IBigStepper vm_);
    function wasRespectedGameTypeWhenCreated() external view returns (bool);
    function weth() external view returns (IDelayedWETH weth_);

    function __constructor__(GameConstructorParams memory _params) external;
}

// lib/base-contracts/interfaces/L1/IETHLockbox.sol

interface IETHLockbox is IProxyAdminOwnedBase, ISemver, IReinitializableBase {
    error ETHLockbox_Unauthorized();
    error ETHLockbox_Paused();
    error ETHLockbox_InsufficientBalance();
    error ETHLockbox_NoWithdrawalTransactions();
    error ETHLockbox_DifferentSuperchainConfig();

    event Initialized(uint8 version);
    event ETHLocked(IOptimismPortal2 indexed portal, uint256 amount);
    event ETHUnlocked(IOptimismPortal2 indexed portal, uint256 amount);
    event PortalAuthorized(IOptimismPortal2 indexed portal);
    event LockboxAuthorized(IETHLockbox indexed lockbox);
    event LiquidityMigrated(IETHLockbox indexed lockbox, uint256 amount);
    event LiquidityReceived(IETHLockbox indexed lockbox, uint256 amount);

    function initialize(ISystemConfig _systemConfig, IOptimismPortal2[] calldata _portals) external;
    function systemConfig() external view returns (ISystemConfig);
    function paused() external view returns (bool);
    function authorizedPortals(IOptimismPortal2) external view returns (bool);
    function authorizedLockboxes(IETHLockbox) external view returns (bool);
    function receiveLiquidity() external payable;
    function lockETH() external payable;
    function unlockETH(uint256 _value) external;
    function authorizePortal(IOptimismPortal2 _portal) external;
    function authorizeLockbox(IETHLockbox _lockbox) external;
    function migrateLiquidity(IETHLockbox _lockbox) external;
    function superchainConfig() external view returns (ISuperchainConfig);

    function __constructor__() external;
}

// lib/base-contracts/interfaces/L1/IOptimismPortal2.sol

interface IOptimismPortal2 is IProxyAdminOwnedBase {
    error ContentLengthMismatch();
    error EmptyItem();
    error InvalidDataRemainder();
    error InvalidHeader();
    error ReinitializableBase_ZeroInitVersion();
    error OptimismPortal_AlreadyFinalized();
    error OptimismPortal_BadTarget();
    error OptimismPortal_CallPaused();
    error OptimismPortal_CalldataTooLarge();
    error OptimismPortal_NotAllowedOnCGTMode();
    error OptimismPortal_GasEstimation();
    error OptimismPortal_GasLimitTooLow();
    error OptimismPortal_ImproperDisputeGame();
    error OptimismPortal_InvalidDisputeGame();
    error OptimismPortal_InvalidMerkleProof();
    error OptimismPortal_InvalidOutputRootProof();
    error OptimismPortal_InvalidProofTimestamp();
    error OptimismPortal_InvalidRootClaim();
    error OptimismPortal_NoReentrancy();
    error OptimismPortal_ProofNotOldEnough();
    error OptimismPortal_Unproven();
    error OptimismPortal_InvalidLockboxState();
    error OutOfGas();
    error UnexpectedList();
    error UnexpectedString();

    event Initialized(uint8 version);
    event TransactionDeposited(address indexed from, address indexed to, uint256 indexed version, bytes opaqueData);
    event WithdrawalFinalized(bytes32 indexed withdrawalHash, bool success);
    event WithdrawalProven(bytes32 indexed withdrawalHash, address indexed from, address indexed to);
    event WithdrawalProvenExtension1(bytes32 indexed withdrawalHash, address indexed proofSubmitter);

    receive() external payable;

    function anchorStateRegistry() external view returns (IAnchorStateRegistry);
    function ethLockbox() external view returns (IETHLockbox);
    function checkWithdrawal(bytes32 _withdrawalHash, address _proofSubmitter) external view;
    function depositTransaction(
        address _to,
        uint256 _value,
        uint64 _gasLimit,
        bool _isCreation,
        bytes memory _data
    )
        external
        payable;
    function disputeGameBlacklist(IDisputeGame _disputeGame) external view returns (bool);
    function disputeGameFactory() external view returns (IDisputeGameFactory);
    function disputeGameFinalityDelaySeconds() external view returns (uint256);
    function donateETH() external payable;
    function superchainConfig() external view returns (ISuperchainConfig);
    function finalizeWithdrawalTransaction(Types.WithdrawalTransaction memory _tx) external;
    function finalizeWithdrawalTransactionExternalProof(
        Types.WithdrawalTransaction memory _tx,
        address _proofSubmitter
    )
        external;
    function finalizedWithdrawals(bytes32) external view returns (bool);
    function guardian() external view returns (address);
    function initialize(ISystemConfig _systemConfig, IAnchorStateRegistry _anchorStateRegistry) external;
    function initVersion() external view returns (uint8);
    function l2Sender() external view returns (address);
    function minimumGasLimit(uint64 _byteCount) external pure returns (uint64);
    function numProofSubmitters(bytes32 _withdrawalHash) external view returns (uint256);
    function params() external view returns (uint128 prevBaseFee, uint64 prevBoughtGas, uint64 prevBlockNum); // nosemgrep
    function paused() external view returns (bool);
    function proofMaturityDelaySeconds() external view returns (uint256);
    function proofSubmitters(bytes32, uint256) external view returns (address);
    function proveWithdrawalTransaction(
        Types.WithdrawalTransaction memory _tx,
        uint256 _disputeGameIndex,
        Types.OutputRootProof memory _outputRootProof,
        bytes[] memory _withdrawalProof
    )
        external;
    function provenWithdrawals(
        bytes32,
        address
    )
        external
        view
        returns (IDisputeGame disputeGameProxy, uint64 timestamp);
    function respectedGameType() external view returns (GameType);
    function respectedGameTypeUpdatedAt() external view returns (uint64);
    function systemConfig() external view returns (ISystemConfig);
    function version() external pure returns (string memory);

    function __constructor__(uint256 _proofMaturityDelaySeconds) external;
}

// lib/base-contracts/src/L1/SystemConfig.sol

// Contracts

// Libraries

// Interfaces

/// @custom:proxied true
/// @title SystemConfig
/// @notice The SystemConfig contract is used to manage configuration of an Optimism network.
///         All configuration is stored on L1 and picked up by L2 as part of the derviation of
///         the L2 chain.
contract SystemConfig is ProxyAdminOwnedBase, OwnableUpgradeable, ReinitializableBase, ISemver {
    /// @notice Enum representing different types of updates.
    /// @custom:value BATCHER              Represents an update to the batcher hash.
    /// @custom:value FEE_SCALARS          Represents an update to l1 data fee scalars.
    /// @custom:value GAS_LIMIT            Represents an update to gas limit on L2.
    /// @custom:value UNSAFE_BLOCK_SIGNER  Represents an update to the signer key for unsafe
    ///                                    block distrubution.
    /// @custom:value EIP_1559_PARAMS     Represents an update to EIP-1559 parameters.
    /// @custom:value OPERATOR_FEE_PARAMS Represents an update to operator fee parameters.
    /// @custom:value MIN_BASE_FEE        Represents an update to the minimum base fee.
    /// @custom:value DA_FOOTPRINT_GAS_SCALAR Represents an update to the DA footprint gas scalar.
    enum UpdateType {
        BATCHER,
        FEE_SCALARS,
        GAS_LIMIT,
        UNSAFE_BLOCK_SIGNER,
        EIP_1559_PARAMS,
        OPERATOR_FEE_PARAMS,
        MIN_BASE_FEE,
        DA_FOOTPRINT_GAS_SCALAR
    }

    /// @notice Struct representing the addresses of L1 system contracts. These should be the
    ///         contracts that users interact with (not implementations for proxied contracts)
    ///         and are network specific.
    struct Addresses {
        address l1CrossDomainMessenger;
        address l1ERC721Bridge;
        address l1StandardBridge;
        address optimismPortal;
        address optimismMintableERC20Factory;
        address delayedWETH;
    }

    /// @notice Version identifier, used for upgrades.
    uint256 public constant VERSION = 0;

    /// @notice Storage slot that the unsafe block signer is stored at.
    ///         Storing it at this deterministic storage slot allows for decoupling the storage
    ///         layout from the way that `solc` lays out storage. The `op-node` uses a storage
    ///         proof to fetch this value.
    /// @dev    NOTE: this value will be migrated to another storage slot in a future version.
    ///         User input should not be placed in storage in this contract until this migration
    ///         happens. It is unlikely that keccak second preimage resistance will be broken,
    ///         but it is better to be safe than sorry.
    bytes32 public constant UNSAFE_BLOCK_SIGNER_SLOT = keccak256("systemconfig.unsafeblocksigner");

    /// @notice Storage slot that the L1CrossDomainMessenger address is stored at.
    bytes32 public constant L1_CROSS_DOMAIN_MESSENGER_SLOT =
        bytes32(uint256(keccak256("systemconfig.l1crossdomainmessenger")) - 1);

    /// @notice Storage slot that the L1ERC721Bridge address is stored at.
    bytes32 public constant L1_ERC_721_BRIDGE_SLOT = bytes32(uint256(keccak256("systemconfig.l1erc721bridge")) - 1);

    /// @notice Storage slot that the L1StandardBridge address is stored at.
    bytes32 public constant L1_STANDARD_BRIDGE_SLOT = bytes32(uint256(keccak256("systemconfig.l1standardbridge")) - 1);

    /// @notice Storage slot that the OptimismPortal address is stored at.
    bytes32 public constant OPTIMISM_PORTAL_SLOT = bytes32(uint256(keccak256("systemconfig.optimismportal")) - 1);

    /// @notice Storage slot that the OptimismMintableERC20Factory address is stored at.
    bytes32 public constant OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT =
        bytes32(uint256(keccak256("systemconfig.optimismmintableerc20factory")) - 1);

    /// @notice Storage slot that the DelayedWETH address is stored at.
    bytes32 public constant DELAYED_WETH_SLOT = bytes32(uint256(keccak256("systemconfig.delayedweth")) - 1);

    /// @notice Storage slot that the batch inbox address is stored at.
    bytes32 public constant BATCH_INBOX_SLOT = bytes32(uint256(keccak256("systemconfig.batchinbox")) - 1);

    /// @notice Storage slot for block at which the op-node can start searching for logs from.
    bytes32 public constant START_BLOCK_SLOT = bytes32(uint256(keccak256("systemconfig.startBlock")) - 1);

    /// @notice The maximum gas limit that can be set for L2 blocks. This limit is used to enforce that the blocks
    ///         on L2 are not too large to process and prove. Over time, this value can be increased as various
    ///         optimizations and improvements are made to the system at large.
    uint64 internal constant MAX_GAS_LIMIT = 500_000_000;

    /// @notice Fixed L2 gas overhead. Used as part of the L2 fee calculation.
    ///         Deprecated since the Ecotone network upgrade
    uint256 public overhead;

    /// @notice Dynamic L2 gas overhead. Used as part of the L2 fee calculation.
    ///         The most significant byte is used to determine the version since the
    ///         Ecotone network upgrade.
    uint256 public scalar;

    /// @notice Identifier for the batcher.
    ///         For version 1 of this configuration, this is represented as an address left-padded
    ///         with zeros to 32 bytes.
    bytes32 public batcherHash;

    /// @notice L2 block gas limit.
    uint64 public gasLimit;

    /// @notice Basefee scalar value. Part of the L2 fee calculation since the Ecotone network upgrade.
    uint32 public basefeeScalar;

    /// @notice Blobbasefee scalar value. Part of the L2 fee calculation since the Ecotone network upgrade.
    uint32 public blobbasefeeScalar;

    /// @notice The configuration for the deposit fee market.
    ///         Used by the OptimismPortal to meter the cost of buying L2 gas on L1.
    ///         Set as internal with a getter so that the struct is returned instead of a tuple.
    IResourceMetering.ResourceConfig internal _resourceConfig;

    /// @notice The EIP-1559 base fee max change denominator.
    uint32 public eip1559Denominator;

    /// @notice The EIP-1559 elasticity multiplier.
    uint32 public eip1559Elasticity;

    /// @notice The operator fee scalar.
    uint32 public operatorFeeScalar;

    /// @notice The operator fee constant.
    uint64 public operatorFeeConstant;

    // @notice The DA footprint gas scalar.
    uint16 public daFootprintGasScalar;

    /// @notice The L2 chain ID that this SystemConfig configures.
    uint256 public l2ChainId;

    /// @notice The SuperchainConfig contract that manages the pause state.
    ISuperchainConfig public superchainConfig;

    /// @notice The minimum base fee, in wei.
    uint64 public minBaseFee;

    /// @notice Bytes32 feature flag name to boolean enabled value.
    mapping(bytes32 => bool) public isFeatureEnabled;

    /// @notice Emitted when configuration is updated.
    /// @param version    SystemConfig version.
    /// @param updateType Type of update.
    /// @param data       Encoded update data.
    event ConfigUpdate(uint256 indexed version, UpdateType indexed updateType, bytes data);

    /// @notice Emitted when a feature is set.
    /// @param feature Feature that was set.
    /// @param enabled Whether the feature is enabled.
    event FeatureSet(bytes32 indexed feature, bool indexed enabled);

    /// @notice Thrown when attempting to enable/disable a feature when already enabled/disabled,
    ///         respectively.
    error SystemConfig_InvalidFeatureState();

    /// @notice Semantic version.
    /// @custom:semver 3.13.2
    function version() public pure virtual returns (string memory) {
        return "3.13.2";
    }

    /// @notice Constructs the SystemConfig contract.
    /// @dev    START_BLOCK_SLOT is set to type(uint256).max here so that it will be a dead value
    ///         in the singleton.
    constructor() ReinitializableBase(4) {
        Storage.setUint(START_BLOCK_SLOT, type(uint256).max);
        _disableInitializers();
    }

    /// @notice Initializer.
    ///         The resource config must be set before the require check.
    /// @param _owner             Initial owner of the contract.
    /// @param _basefeeScalar     Initial basefee scalar value.
    /// @param _blobbasefeeScalar Initial blobbasefee scalar value.
    /// @param _batcherHash       Initial batcher hash.
    /// @param _gasLimit          Initial gas limit.
    /// @param _unsafeBlockSigner Initial unsafe block signer address.
    /// @param _config            Initial ResourceConfig.
    /// @param _batchInbox        Batch inbox address. An identifier for the op-node to find
    ///                           canonical data.
    /// @param _addresses         Set of L1 contract addresses. These should be the proxies.
    /// @param _l2ChainId         The L2 chain ID that this SystemConfig configures.
    /// @param _superchainConfig  The SuperchainConfig contract address.
    function initialize(
        address _owner,
        uint32 _basefeeScalar,
        uint32 _blobbasefeeScalar,
        bytes32 _batcherHash,
        uint64 _gasLimit,
        address _unsafeBlockSigner,
        IResourceMetering.ResourceConfig memory _config,
        address _batchInbox,
        SystemConfig.Addresses memory _addresses,
        uint256 _l2ChainId,
        ISuperchainConfig _superchainConfig
    )
        public
        reinitializer(initVersion())
    {
        // Initialization transactions must come from the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // Now perform initialization logic.
        __Ownable_init();
        transferOwnership(_owner);

        // These are set in ascending order of their UpdateTypes.
        _setBatcherHash(_batcherHash);
        _setGasConfigEcotone({ _basefeeScalar: _basefeeScalar, _blobbasefeeScalar: _blobbasefeeScalar });
        _setGasLimit(_gasLimit);

        Storage.setAddress(UNSAFE_BLOCK_SIGNER_SLOT, _unsafeBlockSigner);
        Storage.setAddress(BATCH_INBOX_SLOT, _batchInbox);
        Storage.setAddress(L1_CROSS_DOMAIN_MESSENGER_SLOT, _addresses.l1CrossDomainMessenger);
        Storage.setAddress(L1_ERC_721_BRIDGE_SLOT, _addresses.l1ERC721Bridge);
        Storage.setAddress(L1_STANDARD_BRIDGE_SLOT, _addresses.l1StandardBridge);
        Storage.setAddress(OPTIMISM_PORTAL_SLOT, _addresses.optimismPortal);
        Storage.setAddress(OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT, _addresses.optimismMintableERC20Factory);
        Storage.setAddress(DELAYED_WETH_SLOT, _addresses.delayedWETH);
        _setStartBlock();

        _setResourceConfig(_config);

        l2ChainId = _l2ChainId;
        superchainConfig = _superchainConfig;
    }

    /// @notice Returns the minimum L2 gas limit that can be safely set for the system to
    ///         operate. The L2 gas limit must be larger than or equal to the amount of
    ///         gas that is allocated for deposits per block plus the amount of gas that
    ///         is allocated for the system transaction.
    ///         This function is used to determine if changes to parameters are safe.
    /// @return uint64 Minimum gas limit.
    function minimumGasLimit() public view returns (uint64) {
        return uint64(_resourceConfig.maxResourceLimit) + uint64(_resourceConfig.systemTxMaxGas);
    }

    /// @notice Returns the maximum L2 gas limit that can be safely set for the system to
    ///         operate. This bound is used to prevent the gas limit from being set too high
    ///         and causing the system to be unable to process and/or prove L2 blocks.
    /// @return uint64 Maximum gas limit.
    function maximumGasLimit() public pure returns (uint64) {
        return MAX_GAS_LIMIT;
    }

    /// @notice High level getter for the unsafe block signer address.
    ///         Unsafe blocks can be propagated across the p2p network if they are signed by the
    ///         key corresponding to this address.
    /// @return addr_ Address of the unsafe block signer.
    function unsafeBlockSigner() public view returns (address addr_) {
        addr_ = Storage.getAddress(UNSAFE_BLOCK_SIGNER_SLOT);
    }

    /// @notice Getter for the L1CrossDomainMessenger address.
    function l1CrossDomainMessenger() public view returns (address addr_) {
        addr_ = Storage.getAddress(L1_CROSS_DOMAIN_MESSENGER_SLOT);
    }

    /// @notice Getter for the L1ERC721Bridge address.
    function l1ERC721Bridge() public view returns (address addr_) {
        addr_ = Storage.getAddress(L1_ERC_721_BRIDGE_SLOT);
    }

    /// @notice Getter for the L1StandardBridge address.
    function l1StandardBridge() public view returns (address addr_) {
        addr_ = Storage.getAddress(L1_STANDARD_BRIDGE_SLOT);
    }

    /// @notice Getter for the DisputeGameFactory address.
    function disputeGameFactory() public view returns (address addr_) {
        IOptimismPortal2 portal = IOptimismPortal2(payable(optimismPortal()));
        addr_ = address(portal.disputeGameFactory());
    }

    /// @notice Getter for the OptimismPortal address.
    function optimismPortal() public view returns (address addr_) {
        addr_ = Storage.getAddress(OPTIMISM_PORTAL_SLOT);
    }

    /// @notice Getter for the OptimismMintableERC20Factory address.
    function optimismMintableERC20Factory() public view returns (address addr_) {
        addr_ = Storage.getAddress(OPTIMISM_MINTABLE_ERC20_FACTORY_SLOT);
    }

    /// @notice Getter for the DelayedWETH address.
    function delayedWETH() public view returns (address addr_) {
        addr_ = Storage.getAddress(DELAYED_WETH_SLOT);
    }

    /// @notice Consolidated getter for the Addresses struct.
    function getAddresses() external view returns (Addresses memory) {
        return Addresses({
            l1CrossDomainMessenger: l1CrossDomainMessenger(),
            l1ERC721Bridge: l1ERC721Bridge(),
            l1StandardBridge: l1StandardBridge(),
            optimismPortal: optimismPortal(),
            optimismMintableERC20Factory: optimismMintableERC20Factory(),
            delayedWETH: delayedWETH()
        });
    }

    /// @notice Getter for the BatchInbox address.
    function batchInbox() external view returns (address addr_) {
        addr_ = Storage.getAddress(BATCH_INBOX_SLOT);
    }

    /// @notice Getter for the StartBlock number.
    function startBlock() external view returns (uint256 startBlock_) {
        startBlock_ = Storage.getUint(START_BLOCK_SLOT);
    }

    /// @notice Updates the unsafe block signer address. Can only be called by the owner.
    /// @param _unsafeBlockSigner New unsafe block signer address.
    function setUnsafeBlockSigner(address _unsafeBlockSigner) external onlyOwner {
        _setUnsafeBlockSigner(_unsafeBlockSigner);
    }

    /// @notice Updates the unsafe block signer address.
    /// @param _unsafeBlockSigner New unsafe block signer address.
    function _setUnsafeBlockSigner(address _unsafeBlockSigner) internal {
        Storage.setAddress(UNSAFE_BLOCK_SIGNER_SLOT, _unsafeBlockSigner);

        bytes memory data = abi.encode(_unsafeBlockSigner);
        emit ConfigUpdate(VERSION, UpdateType.UNSAFE_BLOCK_SIGNER, data);
    }

    /// @notice Updates the batcher hash by formatting a provided batcher address.
    /// @param _batcher New batcher address.
    function setBatcherHash(address _batcher) external onlyOwner {
        _setBatcherHash(bytes32(uint256(uint160(_batcher))));
    }

    /// @notice Updates the batcher hash. Can only be called by the owner.
    /// @param _batcherHash New batcher hash.
    function setBatcherHash(bytes32 _batcherHash) external onlyOwner {
        _setBatcherHash(_batcherHash);
    }

    /// @notice Internal function for updating the batcher hash.
    /// @param _batcherHash New batcher hash.
    function _setBatcherHash(bytes32 _batcherHash) internal {
        batcherHash = _batcherHash;

        bytes memory data = abi.encode(_batcherHash);
        emit ConfigUpdate(VERSION, UpdateType.BATCHER, data);
    }

    /// @notice Updates gas config. Can only be called by the owner.
    ///         Deprecated in favor of setGasConfigEcotone since the Ecotone upgrade.
    /// @param _overhead New overhead value.
    /// @param _scalar   New scalar value.
    function setGasConfig(uint256 _overhead, uint256 _scalar) external onlyOwner {
        _setGasConfig(_overhead, _scalar);
    }

    /// @notice Internal function for updating the gas config.
    /// @param _overhead New overhead value.
    /// @param _scalar   New scalar value.
    function _setGasConfig(uint256 _overhead, uint256 _scalar) internal {
        require((uint256(0xff) << 248) & _scalar == 0, "SystemConfig: scalar exceeds max.");

        overhead = _overhead;
        scalar = _scalar;

        bytes memory data = abi.encode(_overhead, _scalar);
        emit ConfigUpdate(VERSION, UpdateType.FEE_SCALARS, data);
    }

    /// @notice Updates gas config as of the Ecotone upgrade. Can only be called by the owner.
    /// @param _basefeeScalar     New basefeeScalar value.
    /// @param _blobbasefeeScalar New blobbasefeeScalar value.
    function setGasConfigEcotone(uint32 _basefeeScalar, uint32 _blobbasefeeScalar) external onlyOwner {
        _setGasConfigEcotone(_basefeeScalar, _blobbasefeeScalar);
    }

    /// @notice Internal function for updating the fee scalars as of the Ecotone upgrade.
    /// @param _basefeeScalar     New basefeeScalar value.
    /// @param _blobbasefeeScalar New blobbasefeeScalar value.
    function _setGasConfigEcotone(uint32 _basefeeScalar, uint32 _blobbasefeeScalar) internal {
        basefeeScalar = _basefeeScalar;
        blobbasefeeScalar = _blobbasefeeScalar;

        scalar = (uint256(0x01) << 248) | (uint256(_blobbasefeeScalar) << 32) | _basefeeScalar;

        bytes memory data = abi.encode(overhead, scalar);
        emit ConfigUpdate(VERSION, UpdateType.FEE_SCALARS, data);
    }

    /// @notice Updates the L2 gas limit. Can only be called by the owner.
    /// @param _gasLimit New gas limit.
    function setGasLimit(uint64 _gasLimit) external onlyOwner {
        _setGasLimit(_gasLimit);
    }

    /// @notice Internal function for updating the L2 gas limit.
    /// @param _gasLimit New gas limit.
    function _setGasLimit(uint64 _gasLimit) internal {
        require(_gasLimit >= minimumGasLimit(), "SystemConfig: gas limit too low");
        require(_gasLimit <= maximumGasLimit(), "SystemConfig: gas limit too high");
        gasLimit = _gasLimit;

        bytes memory data = abi.encode(_gasLimit);
        emit ConfigUpdate(VERSION, UpdateType.GAS_LIMIT, data);
    }

    /// @notice Updates the EIP-1559 parameters of the chain. Can only be called by the owner.
    /// @param _denominator EIP-1559 base fee max change denominator.
    /// @param _elasticity  EIP-1559 elasticity multiplier.
    function setEIP1559Params(uint32 _denominator, uint32 _elasticity) external onlyOwner {
        _setEIP1559Params(_denominator, _elasticity);
    }

    /// @notice Internal function for updating the EIP-1559 parameters.
    function _setEIP1559Params(uint32 _denominator, uint32 _elasticity) internal {
        // require the parameters have sane values:
        require(_denominator >= 1, "SystemConfig: denominator must be >= 1");
        require(_elasticity >= 1, "SystemConfig: elasticity must be >= 1");
        eip1559Denominator = _denominator;
        eip1559Elasticity = _elasticity;

        bytes memory data = abi.encode(uint256(_denominator) << 32 | uint64(_elasticity));
        emit ConfigUpdate(VERSION, UpdateType.EIP_1559_PARAMS, data);
    }

    /// @notice Updates the minimum base fee. Can only be called by the owner.
    ///         Setting this value to 0 is equivalent to disabling the min base fee feature
    /// @param _minBaseFee New minimum base fee.
    function setMinBaseFee(uint64 _minBaseFee) external onlyOwner {
        _setMinBaseFee(_minBaseFee);
    }

    /// @notice Internal function for updating the minimum base fee.
    function _setMinBaseFee(uint64 _minBaseFee) internal {
        minBaseFee = _minBaseFee;

        bytes memory data = abi.encode(_minBaseFee);
        emit ConfigUpdate(VERSION, UpdateType.MIN_BASE_FEE, data);
    }

    /// @notice Updates the operator fee parameters. Can only be called by the owner.
    /// @param _operatorFeeScalar New operator fee scalar.
    /// @param _operatorFeeConstant New operator fee constant.
    function setOperatorFeeScalars(uint32 _operatorFeeScalar, uint64 _operatorFeeConstant) external onlyOwner {
        _setOperatorFeeScalars(_operatorFeeScalar, _operatorFeeConstant);
    }

    /// @notice Internal function for updating the operator fee parameters.
    function _setOperatorFeeScalars(uint32 _operatorFeeScalar, uint64 _operatorFeeConstant) internal {
        operatorFeeScalar = _operatorFeeScalar;
        operatorFeeConstant = _operatorFeeConstant;

        bytes memory data = abi.encode(uint256(_operatorFeeScalar) << 64 | _operatorFeeConstant);
        emit ConfigUpdate(VERSION, UpdateType.OPERATOR_FEE_PARAMS, data);
    }

    /// @notice Updates the DA footprint gas scalar. Can only be called by the owner.
    /// @param _daFootprintGasScalar New DA footprint gas scalar.
    function setDAFootprintGasScalar(uint16 _daFootprintGasScalar) external onlyOwner {
        _setDAFootprintGasScalar(_daFootprintGasScalar);
    }

    /// @notice Internal function for updating the DA footprint gas scalar.
    function _setDAFootprintGasScalar(uint16 _dAFootprintGasScalar) internal {
        daFootprintGasScalar = _dAFootprintGasScalar;

        bytes memory data = abi.encode(_dAFootprintGasScalar);
        emit ConfigUpdate(VERSION, UpdateType.DA_FOOTPRINT_GAS_SCALAR, data);
    }

    /// @notice Sets the start block in a backwards compatible way. Proxies
    ///         that were initialized before the startBlock existed in storage
    ///         can have their start block set by a user provided override.
    ///         A start block of 0 indicates that there is no override and the
    ///         start block will be set by `block.number`.
    /// @dev    This logic is used to patch legacy deployments with new storage values.
    ///         Use the override if it is provided as a non zero value and the value
    ///         has not already been set in storage. Use `block.number` if the value
    ///         has already been set in storage
    function _setStartBlock() internal {
        if (Storage.getUint(START_BLOCK_SLOT) == 0) {
            Storage.setUint(START_BLOCK_SLOT, block.number);
        }
    }

    /// @notice A getter for the resource config.
    ///         Ensures that the struct is returned instead of a tuple.
    /// @return ResourceConfig
    function resourceConfig() external view returns (IResourceMetering.ResourceConfig memory) {
        return _resourceConfig;
    }

    /// @notice An internal setter for the resource config.
    ///         Ensures that the config is sane before storing it by checking for invariants.
    ///         In the future, this method may emit an event that the `op-node` picks up
    ///         for when the resource config is changed.
    /// @param _config The new resource config.
    function _setResourceConfig(IResourceMetering.ResourceConfig memory _config) internal {
        // Min base fee must be less than or equal to max base fee.
        require(
            _config.minimumBaseFee <= _config.maximumBaseFee, "SystemConfig: min base fee must be less than max base"
        );
        // Base fee change denominator must be greater than 1.
        require(_config.baseFeeMaxChangeDenominator > 1, "SystemConfig: denominator must be larger than 1");
        // Max resource limit plus system tx gas must be less than or equal to the L2 gas limit.
        // The gas limit must be increased before these values can be increased.
        require(_config.maxResourceLimit + _config.systemTxMaxGas <= gasLimit, "SystemConfig: gas limit too low");
        // Elasticity multiplier must be greater than 0.
        require(_config.elasticityMultiplier > 0, "SystemConfig: elasticity multiplier cannot be 0");
        // No precision loss when computing target resource limit.
        require(
            ((_config.maxResourceLimit / _config.elasticityMultiplier) * _config.elasticityMultiplier)
                == _config.maxResourceLimit,
            "SystemConfig: precision loss with target resource limit"
        );

        _resourceConfig = _config;
    }

    /// @notice Sets a feature flag enabled or disabled. Can only be called by the ProxyAdmin or
    ///         its owner.
    /// @param _feature Feature to set.
    /// @param _enabled Whether the feature should be enabled or disabled.
    function setFeature(bytes32 _feature, bool _enabled) external {
        // Features can only be set by the ProxyAdmin or its owner.
        _assertOnlyProxyAdminOrProxyAdminOwner();

        // As a sanity check, prevent users from enabling the feature if already enabled or
        // disabling the feature if already disabled. This helps to prevent accidental misuse.
        if (_enabled == isFeatureEnabled[_feature]) {
            revert SystemConfig_InvalidFeatureState();
        }

        // Handle feature-specific safety logic here.
        if (_feature == Features.ETH_LOCKBOX) {
            // It would probably better to check that the ETHLockbox contract is set inside the
            // OptimismPortal2 contract before you're allowed to enable the feature here, but the
            // portal checks that the feature is set before allowing you to set the lockbox, so
            // these checks are good enough.

            // Lockbox shouldn't be unset if the ethLockbox address is still configured in the
            // OptimismPortal2 contract. Doing so would cause the system to start keeping ETH in
            // the portal. This check means there's no way to stop using ETHLockbox at the moment
            // after it's been configured (which is expected).
            if (
                isFeatureEnabled[_feature] && !_enabled
                    && address(IOptimismPortal2(payable(optimismPortal())).ethLockbox()) != address(0)
            ) {
                revert SystemConfig_InvalidFeatureState();
            }

            // Lockbox can't be set or unset if the system is currently paused because it would
            // change the pause identifier which would potentially cause the system to become
            // unpaused unexpectedly.
            if (paused()) {
                revert SystemConfig_InvalidFeatureState();
            }
        }

        // Set the feature.
        isFeatureEnabled[_feature] = _enabled;

        // Emit an event.
        emit FeatureSet(_feature, _enabled);
    }

    /// @notice Returns the current pause state for this network. If the network is using
    ///         ETHLockbox, the system is paused if either the global pause is active or the pause
    ///         is active where the ETHLockbox address is used as the identifier. If the network is
    ///         not using ETHLockbox, the system is paused if either the global pause is active or
    ///         the pause is active where the OptimismPortal address is used as the identifier.
    /// @return bool True if the system is paused, false otherwise.
    function paused() public view returns (bool) {
        // Determine the appropriate chain identifier based on the feature flags.
        address identifier = isFeatureEnabled[Features.ETH_LOCKBOX]
            ? address(IOptimismPortal2(payable(optimismPortal())).ethLockbox())
            : address(optimismPortal());

        // Check if either global or local pause is active.
        return superchainConfig.paused(address(0)) || superchainConfig.paused(identifier);
    }

    /// @notice Returns the guardian address of the SuperchainConfig.
    /// @return address The guardian address.
    function guardian() public view returns (address) {
        return superchainConfig.guardian();
    }

    /// @custom:legacy
    /// @notice Returns whether the custom gas token feature is enabled.
    /// @return bool True if the custom gas token feature is enabled, false otherwise.
    function isCustomGasToken() public view returns (bool) {
        return isFeatureEnabled[Features.CUSTOM_GAS_TOKEN];
    }
}
