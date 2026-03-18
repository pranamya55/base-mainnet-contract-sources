// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice A library for computing merkle tree roots and proofs.
/// @dev This library produces complete trees. If a node does not have a sibling, it is combined with itself.
library Merkle {
    /// @notice A merkle tree.
    /// @dev Contains the leaf hashes at the 0th level, pairwise hashes in the following, and the root in the last.
    struct Tree {
        bytes32[][] hashes;
    }

    function newTreeFromData(bytes[] memory leaves) internal pure returns (Tree memory tree) {
        bytes32[] memory leafDigests = new bytes32[](leaves.length);
        for (uint256 i; i < leaves.length; i++) {
            leafDigests[i] = hashLeaf(leaves[i]);
        }
        return newTree(leafDigests);
    }

    /// @notice Creates a new merkle tree.
    /// @param leafs The leafs of the tree computed with `hashLeaf`.
    function newTree(bytes32[] memory leafs) internal pure returns (Tree memory tree) {
        if (leafs.length == 0) {
            return Tree({hashes: new bytes32[][](0)});
        }

        uint256 depth = Math.log2(leafs.length);
        // round up to the next power of 2
        if (leafs.length != 1 << depth || leafs.length == 1) {
            depth++;
        }

        // +1 for the leafs
        tree.hashes = new bytes32[][](depth + 1);
        tree.hashes[0] = leafs;

        for (uint256 i; i < depth; ++i) {
            tree.hashes[i + 1] = hashPairs(tree.hashes[i], false);
        }
    }

    /// @notice Hashes the raw data of a leaf.
    /// @dev This uses double keccak256 hashing instead of a single one to prevent second-preimage attacks.
    function hashLeaf(bytes memory data) internal pure returns (bytes32) {
        bytes32 hash = keccak256(data);
        assembly {
            mstore(0x00, hash)
            hash := keccak256(0x00, 0x20)
        }
        return hash;
    }

    /// @notice Returns the root of the merkle tree.
    function root(Tree memory tree) internal pure returns (bytes32) {
        if (tree.hashes.length == 0) {
            return bytes32(0);
        }
        return tree.hashes[tree.hashes.length - 1][0];
    }

    /// @notice Computes a merkle proof compatible with OZ's merkle proof validation.
    function proof(Tree memory tree, uint256 leafIdx) internal pure returns (bytes32[] memory) {
        uint256 len = proofLength(tree);
        bytes32[] memory proof_ = new bytes32[](len);

        for (uint256 i; i < len; ++i) {
            bool odd = (leafIdx % 2) == 1;
            uint256 neighbour = odd ? leafIdx - 1 : leafIdx == tree.hashes[i].length - 1 ? leafIdx : leafIdx + 1;

            proof_[i] = tree.hashes[i][neighbour];

            leafIdx /= 2;
        }
        return proof_;
    }

    function proofLength(Tree memory tree) internal pure returns (uint256) {
        // Minus one because proof don't contain the highest level of the tree
        // (i.e. the merkle root).
        return levels(tree) - 1;
    }

    function levels(Tree memory tree) internal pure returns (uint256) {
        return tree.hashes.length;
    }

    function numLeafs(Tree memory tree) internal pure returns (uint256) {
        return tree.hashes[0].length;
    }

    /// @notice Computes the merkle root of the leaves in place.
    /// @dev Caution! This modifies the input array!
    /// @dev This is more efficient than creating a tree and calling `root` on it.
    function computeRootInPlace(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) {
            return bytes32(0);
        }

        // always hash at least once, for the case where leaves.length == 1
        leaves = hashPairs(leaves, true);
        while (leaves.length > 1) {
            leaves = hashPairs(leaves, true);
        }
        return leaves[0];
    }

    function hashPairs(bytes32[] memory leaves, bool inPlace) internal pure returns (bytes32[] memory) {
        uint256 lenOld = leaves.length;
        uint256 lenNew = lenOld / 2;

        bool odd = lenOld % 2 != 0;
        if (odd) {
            lenNew++;
        }

        bytes32[] memory h = leaves;
        if (!inPlace) {
            h = new bytes32[](lenNew);
        }

        uint256 end = odd ? lenNew - 1 : lenNew;
        for (uint256 i; i < end; ++i) {
            h[i] = hashPair(leaves[2 * i], leaves[2 * i + 1]);
        }

        if (odd) {
            h[lenNew - 1] = hashPair(leaves[lenOld - 1], leaves[lenOld - 1]);
        }

        if (inPlace) {
            assembly {
                mstore(h, lenNew)
            }
        }

        return h;
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? efficientHash(a, b) : efficientHash(b, a);
    }

    function efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
