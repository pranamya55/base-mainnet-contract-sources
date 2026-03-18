// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

import {ConfigChanged} from "echo/interfaces/PlatformEvents.sol";
import {Merkle} from "echo/Merkle.sol";
import {IGenericRegistry} from "echo/interfaces/IGenericRegistry.sol";
import {GenericRegistryKeys} from "echo/interfaces/GenericRegistryKeys.sol";
import "./Types.sol";
import {UnlockerLib} from "./UnlockerLib.sol";
import {Versioned} from "echo/Versioned.sol";

/// @title Distributor
contract Distributor is Initializable, AccessControlEnumerableUpgradeable, EIP712Upgradeable, Versioned(1, 0, 1) {
    using SafeERC20 for IERC20;
    using PriceLib for Price;

    /// @notice The role allowed to manage any funds related aspects of the contract
    /// @dev This is intended to be controlled by the IM team.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The role allowed to grant ENG_MANAGER_ROLE
    /// @dev This is intended to be controlled by the ENG multisig.
    bytes32 public constant ENG_ADMIN_ROLE = keccak256("ENG_ADMIN_ROLE");

    /// @notice The role allowed to manage engineering related aspects of the contract, that does not involve any funds.
    /// @dev This is intended to be controlled by the ENG team.
    bytes32 public constant ENG_MANAGER_ROLE = keccak256("ENG_MANAGER_ROLE");

    /// @notice The role allowed to trigger a withdrawal of the platform carry.
    /// @dev This is intended to be controlled by the platform backend.
    bytes32 public constant PLATFORM_CARRY_WITHDRAWER_ROLE = keccak256("PLATFORM_CARRY_WITHDRAWER_ROLE");

    /// @notice The role allowed to sign claim data.
    /// @dev This is intended to be controlled by the platform backend.
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    /// @notice The role allowed to pause token claims and carry withdrawals.
    /// @dev This is intended to be controlled by the platform backend.
    /// @dev Keeping this deliberately separate from the `PLATFORM_CARRY_WITHDRAWER_ROLE` since we might want to grant this to some external monitoring in the future
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev The entity UUID for the platform. Note that the platform does **not** have actually have a UUID in our system.
    /// This is an implementation detail to ensure our carry calculation bookkeeping matches other carry receivers.
    bytes16 internal constant PLATFORM_ENTITY_UUID = bytes16(0);

    error InvalidConfiguration(string);
    error DuplicateUser(bytes16 entityUUID);
    error DuplicateCarryWithdrawer(bytes16 entityUUID);
    error CallerNotAllowed(address sender, bytes16 entityUUID, address signer);
    error UnauthorizedPlatformSigner(address signer);
    error UnauthorizedUserSigner(address got, address want);
    error UnknownUser();
    error ClaimExpired(uint256 expiredAt);
    error AmountExceedsClaimable(uint256 amount, uint256 claimableAmount);
    error AmountExceedsWithdrawableCarry(uint256 amount, uint256 withdrawableAmount);
    error WrongTokenDistribution(bytes16 got, bytes16 want);
    error UnexpectedClaimerMerkleRoot(bytes32[] leafs, bytes32 got, bytes32 want);
    error InvalidClaimerMerkleProof(bytes32 leaf, bytes32 got, bytes32 want);
    error Disabled();

    event Claimed(
        bytes16 indexed tokenDistributionUUID,
        bytes16 indexed entityUUID,
        address indexed receiver,
        uint256 amount,
        uint256 amountUSDC,
        uint256 amountCarry
    );

    event CarryWithdrawn(
        bytes16 indexed tokenDistributionUUID, bytes16 indexed entityUUID, address indexed receiver, uint256 amount
    );

    struct ClaimerState {
        uint256 amountClaimed;
        uint64 amountClaimedUSDC;
    }

    /// @dev Equivalent to CarryWithdrawer, but without the entity UUID since we will have it as key on the mapping.
    struct CarryWithdrawerWithoutUUID {
        address signer;
        uint16 carryBPS;
    }

    /// @notice The UnlockWallet provided by the project that gradually unlocks SPV assets.
    UnlockerLib.Unlocker public unlocker;

    /// @notice The GenericRegistry contract which stores the platform specific carry receiver.
    IGenericRegistry public genericRegistry;

    /// @notice  The token that will be unlocked/released.
    IERC20 public token;

    /// @notice Flag to enable/disable token claims and carry withdrawals.
    bool public isEnabled;

    /// @notice Flag to enable/disable the forced distribution mode.
    /// @dev When enabled, the token claim and carry withdrawal functions do not require signatures from the user signer.
    bool public isForcedDistributionModeEnabled;

    /// @notice The UUID of the token distribution.
    bytes16 public tokenDistributionUUID;

    /// @notice  The total amount invested in the project across all users in USDC.
    /// @dev This is the sum of all `amountInvestedUSDC` in `usersSettings`.
    /// @dev It is used to compute the relative share of the total unlocked tokens for each state.
    uint64 public totalAmountInvestedUSDC;

    /// @notice The total carry in basis points.
    uint16 public totalCarryBPS;

    /// @notice The total amount of tokens claimed by users.
    uint256 public totalClaimed;

    /// @notice The total amount of carry that has been generated, i.e. deducted from user's claims.
    uint256 public totalCarryGenerated;

    /// @notice The total amount of carry withdrawn by carry receivers.
    uint256 public totalCarryWithdrawn;

    /// @notice The carry for the platform in basis points.
    uint16 public platformCarryBPS;

    /// @notice Tracks the amount of tokens each user has already claimed.
    mapping(bytes16 => ClaimerState) private _claimerState;

    /// @notice Tracks the amount of carry each carry withdrawer has withdrawn.
    /// @dev This also keeps track of the platform carry under the PLATFORM_ENTITY_UUID key.
    mapping(bytes16 => uint256) private _carryAmountWithdrawn;

    /// @notice The root of the claimers merkle tree.
    bytes32 public claimersRoot;

    /// @notice Tracks settings for carry withdrawers.
    /// @dev This does not include settings for the platform carry.
    mapping(bytes16 => CarryWithdrawerWithoutUUID) private _carryWithdrawers;

    /// @notice The UUIDs of the carry receivers.
    bytes16[] private _carryWithdrawerUUIDs;

    struct Init {
        IERC20 token;
        bytes16 tokenDistributionUUID;
        UnlockerLib.Unlocker unlocker;
        IGenericRegistry genericRegistry;
        Claimer[] claimers;
        CarryWithdrawer[] carryWithdrawers;
        address adminIM;
        address managerIM;
        address adminENG;
        address managerENG;
        address platformSigner;
        address platformSender;
        bytes32 expectedClaimersRoot;
        uint16 platformCarryBPS;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(Init memory init) external initializer {
        __AccessControlEnumerable_init();
        __EIP712_init("Distributor", "1");

        _setRoleAdmin(ENG_MANAGER_ROLE, ENG_ADMIN_ROLE);
        _setRoleAdmin(SIGNER_ROLE, ENG_MANAGER_ROLE);
        _setRoleAdmin(PLATFORM_CARRY_WITHDRAWER_ROLE, ENG_MANAGER_ROLE);

        // granting IM roles
        _grantRole(DEFAULT_ADMIN_ROLE, init.adminIM);
        _grantRole(MANAGER_ROLE, init.managerIM);

        // granting ENG roles
        _grantRole(ENG_ADMIN_ROLE, init.adminENG);
        _grantRole(ENG_MANAGER_ROLE, init.managerENG);

        // granting platform roles
        _grantRole(SIGNER_ROLE, init.platformSigner);
        _grantRole(PLATFORM_CARRY_WITHDRAWER_ROLE, init.platformSender);
        _grantRole(PAUSER_ROLE, init.platformSender);

        UnlockerLib.validate(init.unlocker);
        unlocker = init.unlocker;
        genericRegistry = init.genericRegistry;
        token = init.token;
        tokenDistributionUUID = init.tokenDistributionUUID;
        platformCarryBPS = init.platformCarryBPS;

        _setClaimers(init.claimers, init.expectedClaimersRoot);
        _setCarryWithdrawerSettings(init.carryWithdrawers);
        isEnabled = true;
    }

    /// @notice Returns the domain separator for this contract.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function claimerStates(bytes16[] calldata entityUUID) external view returns (ClaimerState[] memory) {
        ClaimerState[] memory ret = new ClaimerState[](entityUUID.length);
        for (uint256 i = 0; i < entityUUID.length; i++) {
            ret[i] = _claimerState[entityUUID[i]];
        }
        return ret;
    }

    function claimed(bytes16[] calldata entityUUID) external view returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](entityUUID.length);
        for (uint256 i = 0; i < entityUUID.length; i++) {
            ret[i] = _claimerState[entityUUID[i]].amountClaimed;
        }
        return ret;
    }

    /// @notice Pulls the unlocked tokens from the unlock wallet.
    /// @dev This function can be called by anyone to pull the unlocked tokens from the unlock wallet at any point. However, we commonly expect
    /// it be called when a user claims their tokens.
    function pullUnlockedTokens() public {
        UnlockerLib.release(unlocker);
    }

    /// @notice Claims tokens for a given user. Requires valid signatures of the claim data (user + platform).
    /// @dev The function needs two valid signatures of the claim data (user + platform) to authorize a claim.
    /// There is no additional access control on the function, which allows anyone to execute a claim as long as the signatures are valid.
    /// We chose this approach as it gives us ultimate flexibility in who executes the transaction,
    /// e.g. it could either be send by the user on the frontend or by the platform backend.
    /// Does not require claimer signature if the contract has the`forcedDistributionModeEnabled` flag enabled.
    /// @param claimData The claim data that is signed by the user and the platform.
    /// @param claimSignatureUser The signature of the claim data by the user (EIP-712).
    /// @param claimSignaturePlatform The signature of the claim data by the platform (EIP-712).
    /// @param user The user settings that are used in the merkle proof.
    /// @param merkleProof The merkle proof that is used to verify the user's settings in the merkle tree.
    /// @param pullUnlocked Whether to pull the unlocked tokens from the unlocker contract.
    function claim(
        ClaimData calldata claimData,
        bytes calldata claimSignatureUser,
        bytes calldata claimSignaturePlatform,
        Claimer calldata user,
        bytes32[] calldata merkleProof,
        bool pullUnlocked
    ) external onlyIf(isEnabled) {
        if (pullUnlocked) {
            pullUnlockedTokens();
        }

        _release(claimData, claimSignatureUser, claimSignaturePlatform, user, merkleProof);
    }

    function _release(
        ClaimData calldata claimData,
        bytes calldata claimSignatureUser,
        bytes calldata claimSignaturePlatform,
        Claimer calldata user,
        bytes32[] calldata merkleProof
    ) internal {
        if (claimData.tokenDistributionUUID != tokenDistributionUUID) {
            revert WrongTokenDistribution(claimData.tokenDistributionUUID, tokenDistributionUUID);
        }

        if (block.timestamp >= claimData.expiresAt) {
            revert ClaimExpired(claimData.expiresAt);
        }

        {
            bytes32 leaf = Merkle.hashLeaf(abi.encode(user));
            bytes32 computedRoot = MerkleProof.processProofCalldata(merkleProof, leaf);
            if (computedRoot != claimersRoot) {
                revert InvalidClaimerMerkleProof(leaf, computedRoot, claimersRoot);
            }
        }

        {
            bytes32 digest = ClaimDataLib.digestTypedData(claimData, _domainSeparatorV4());

            if (
                !isForcedDistributionModeEnabled
                    && !SignatureChecker.isValidSignatureNow(user.signer, digest, claimSignatureUser)
            ) {
                address signer = ECDSA.recover(digest, claimSignatureUser);
                revert UnauthorizedUserSigner(signer, user.signer);
            }

            address signerPlatform = ECDSA.recover(digest, claimSignaturePlatform);
            if (!hasRole(SIGNER_ROLE, signerPlatform)) {
                revert UnauthorizedPlatformSigner(signerPlatform);
            }
        }

        ClaimerState storage state = _claimerState[claimData.entityUUID];

        {
            // we don't include the releasable amount here and only consider the actual amount received by the contract
            uint256 claimableAmount = _claimable(claimData.entityUUID, user.amountInvestedUSDC, false);
            if (claimData.amount > claimableAmount) {
                revert AmountExceedsClaimable(claimData.amount, claimableAmount);
            }
        }

        uint256 amountUSDC = claimData.price.convertTokenToUSDC(claimData.amount);
        uint256 amountCarry = _calculateCarryAmount(
            claimData.entityUUID, user.amountInvestedUSDC, user.takeNoCarry, claimData.amount, claimData.price
        );

        state.amountClaimed += claimData.amount;
        state.amountClaimedUSDC += uint64(amountUSDC);

        totalClaimed += claimData.amount;
        totalCarryGenerated += amountCarry;

        emit Claimed(
            tokenDistributionUUID, claimData.entityUUID, claimData.receiver, claimData.amount, amountUSDC, amountCarry
        );

        token.safeTransfer(claimData.receiver, claimData.amount - amountCarry);
    }

    function _calculateCarryAmountUSDC(
        uint256 investedUSDC,
        uint256 claimedUSDC,
        uint256 amountToClaimUSDC,
        uint256 totalCarryBPS_
    ) internal pure returns (uint256) {
        uint256 remainingAmountFreeOfCarryUSDC = investedUSDC > claimedUSDC ? investedUSDC - claimedUSDC : 0;
        uint256 amountWithCarryUSDC =
            amountToClaimUSDC > remainingAmountFreeOfCarryUSDC ? amountToClaimUSDC - remainingAmountFreeOfCarryUSDC : 0;
        return Math.mulDiv(amountWithCarryUSDC, totalCarryBPS_, 10000);
    }

    /// @notice Helper function to compute the carry amount for a given claim.
    /// @dev The function does not verify that the amount can actually be claimed by the entity.
    function _calculateCarryAmount(
        bytes16 entityUUID,
        uint256 amountInvestedUSDC,
        bool takeNoCarry,
        uint256 amountToClaim,
        Price calldata price
    ) internal view returns (uint256) {
        if (takeNoCarry) {
            return 0;
        }

        uint256 amountUSDC = price.convertTokenToUSDC(amountToClaim);
        uint256 amountCarryUSDC = _calculateCarryAmountUSDC(
            amountInvestedUSDC, _claimerState[entityUUID].amountClaimedUSDC, amountUSDC, totalCarryBPS
        );
        uint256 amountCarry = price.convertUSDCToToken(amountCarryUSDC);

        return amountCarry;
    }

    /// @notice Withdraws the carry for a given carry receiver (e.g. a deal lead)
    /// @dev This function should only be used for entities and not for the platform. The platform should use the `withdrawCarryPlatform`
    /// The function needs two valid signatures of the claim data (user + platform) to authorize a claim.
    /// There is no additional access control on the function, which allows anyone to execute a claim as long as the signatures are valid.
    /// We chose this approach as it gives us ultimate flexibility in who executes the transaction,
    /// e.g. it could either be send by the user on the frontend or by the platform backend.
    /// Does not require claimer signature if the contract has the`forcedDistributionModeEnabled` flag enabled.
    /// @param data The data required to withdraw the carry
    /// @param userSignature The signature of the user using EIP-712
    /// @param platformSignature The signature of the platform using EIP-712
    function withdrawCarry(
        CarryWithdrawalData calldata data,
        bytes calldata userSignature,
        bytes calldata platformSignature
    ) external onlyIf(isEnabled) {
        if (data.tokenDistributionUUID != tokenDistributionUUID) {
            revert WrongTokenDistribution(data.tokenDistributionUUID, tokenDistributionUUID);
        }

        if (block.timestamp >= data.expiresAt) {
            revert ClaimExpired(data.expiresAt);
        }

        CarryWithdrawerWithoutUUID memory user = _carryWithdrawers[data.entityUUID];
        if (user.signer == address(0)) {
            revert UnknownUser();
        }

        {
            bytes32 digest = CarryWithdrawalLib.digestTypedData(data, _domainSeparatorV4());

            if (
                !isForcedDistributionModeEnabled
                    && !SignatureChecker.isValidSignatureNow(user.signer, digest, userSignature)
            ) {
                address signer = ECDSA.recover(digest, userSignature);
                revert UnauthorizedUserSigner(signer, user.signer);
            }

            address signerPlatform = ECDSA.recover(digest, platformSignature);
            if (!hasRole(SIGNER_ROLE, signerPlatform)) {
                revert UnauthorizedPlatformSigner(signerPlatform);
            }
        }

        {
            uint256 maxAmount = _carryWithdrawable(data.entityUUID, user.carryBPS);
            if (data.amount > maxAmount) {
                revert AmountExceedsWithdrawableCarry(data.amount, maxAmount);
            }
        }

        _carryAmountWithdrawn[data.entityUUID] += data.amount;
        totalCarryWithdrawn += data.amount;

        emit CarryWithdrawn(data.tokenDistributionUUID, data.entityUUID, data.receiver, data.amount);

        token.safeTransfer(data.receiver, data.amount);
    }

    /// @notice Withdraws the platform carry from the contract.
    /// @dev Carry receivers should use the `withdrawCarry` function.
    /// @param amount The amount of carry in tokens to withdraw
    function withdrawCarryPlatform(uint256 amount) external onlyRole(PLATFORM_CARRY_WITHDRAWER_ROLE) {
        address platformReceiver = genericRegistry.readAddress(GenericRegistryKeys.PLATFORM_CARRY_RECEIVER);
        uint256 maxAmount = _carryWithdrawable(PLATFORM_ENTITY_UUID, platformCarryBPS);
        if (amount > maxAmount) {
            revert AmountExceedsWithdrawableCarry(amount, maxAmount);
        }

        _carryAmountWithdrawn[PLATFORM_ENTITY_UUID] += amount;
        totalCarryWithdrawn += amount;

        emit CarryWithdrawn(tokenDistributionUUID, PLATFORM_ENTITY_UUID, platformReceiver, amount);

        token.safeTransfer(platformReceiver, amount);
    }

    function _carryWithdrawable(bytes16 entityUUID, uint16 carryBPS) internal view returns (uint256) {
        return Math.mulDiv(totalCarryGenerated, carryBPS, totalCarryBPS) - _carryAmountWithdrawn[entityUUID];
    }

    /// @notice Computes the withdrawable carry amount for the platform.
    /// @return The carry withdrawable amount of tokens for the platform.
    function carryWithdrawablePlatform() external view returns (uint256) {
        return _carryWithdrawable(PLATFORM_ENTITY_UUID, platformCarryBPS);
    }

    /// @notice Returns the amount of tokens that have been withdrawn from the carry pool for the platform.
    /// @return The amount of tokens that have been withdrawn from the carry pool for the platform.
    function carryWithdrawnPlatform() external view returns (uint256) {
        return _carryAmountWithdrawn[PLATFORM_ENTITY_UUID];
    }

    /// @notice Computes the carry withdrawable amount for a list of entities.
    /// @dev Not used to calculate the carry withdrawn for the platform as this is handled separately by the platform specific function
    /// `carryWithdrawblePlatform`.
    /// @param entityUUIDs The UUIDs of the entities.
    /// @return The carry withdrawable amount of tokens for each entity.
    function carryWithdrawable(bytes16[] calldata entityUUIDs) external view returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](entityUUIDs.length);
        for (uint256 i = 0; i < entityUUIDs.length; i++) {
            ret[i] = _carryWithdrawable(entityUUIDs[i], _carryWithdrawers[entityUUIDs[i]].carryBPS);
        }
        return ret;
    }

    /// @notice Returns the amount of tokens that have been withdrawn from the carry pool for each entity.
    /// @dev Not used to calculate the carry withdrawn for the platform as this is handled separately by the platform specific function
    /// `carryWithdrawnPlatform`.
    /// @param entityUUIDs The UUIDs of the entities.
    /// @return The amount of tokens that have been withdrawn from the carry pool for each entity.
    function carryWithdrawn(bytes16[] calldata entityUUIDs) external view returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](entityUUIDs.length);
        for (uint256 i = 0; i < entityUUIDs.length; i++) {
            ret[i] = _carryAmountWithdrawn[entityUUIDs[i]];
        }
        return ret;
    }

    function _claimable(bytes16 entityUUID, uint64 amountInvestedUSDC, bool includeReleasable)
        internal
        view
        returns (uint256)
    {
        // we're using the current balance here instead of keeping track of the amount that was pulled in from the unlock wallet
        // to account for any tokens that were manually sent to the distributor contract

        // the total received amount is computed as the current balance + everything that left the contract
        uint256 totalReceived =
            token.balanceOf(address(this)) + (totalClaimed - totalCarryGenerated) + totalCarryWithdrawn;

        if (includeReleasable) {
            totalReceived += UnlockerLib.releasable(unlocker);
        }

        return Math.mulDiv(totalReceived, amountInvestedUSDC, totalAmountInvestedUSDC)
            - _claimerState[entityUUID].amountClaimed;
    }

    /// @notice Computes the claimable amount of tokens for a list of users.
    /// @dev The correctness of the response depends on the correctness of the input parameters,
    /// i.e. whether the user UUIDs and invested amounts are included in the settings as encoded in the corresponding merkle root.
    /// The validity of the passed parameters is NOT validated against the stored merkle root.
    /// @param entityUUIDs The UUIDs of the users.
    /// @param amountsInvestedUSDC The amount of USDC invested by each user.
    /// @param includeReleasable Whether to include the amount releasable from the unlocker in the computation.
    function claimable(bytes16[] calldata entityUUIDs, uint64[] calldata amountsInvestedUSDC, bool includeReleasable)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory ret = new uint256[](entityUUIDs.length);
        for (uint256 i = 0; i < entityUUIDs.length; i++) {
            ret[i] = _claimable(entityUUIDs[i], amountsInvestedUSDC[i], includeReleasable);
        }
        return ret;
    }

    struct CalculateCarryAmountClaimParameters {
        bytes16 entityUUID;
        uint64 amountInvestedUSDC;
        bool takeNoCarry;
        uint256 amountToClaim;
    }

    /// @notice Computes the carry amounts for a list of claims.
    /// @dev This function is intended to be used offchain to compute the carry amounts for a list of claims.
    /// @dev The correctness of the response depends on the correctness of the input parameters,
    /// i.e. whether the entity UUIDs and investment amounts are included in the settings as encoded in the corresponding merkle root.
    /// The validity of the passed parameters is NOT validated against the stored merkle root.
    /// @dev The function does not verify that the amounts can actually be claimed by the entities.
    function calculateCarryAmountForClaims(
        CalculateCarryAmountClaimParameters[] calldata claimParams,
        Price calldata price
    ) external view returns (uint256[] memory) {
        uint256[] memory carryAmounts = new uint256[](claimParams.length);
        for (uint256 i = 0; i < claimParams.length; i++) {
            carryAmounts[i] = _calculateCarryAmount(
                claimParams[i].entityUUID,
                claimParams[i].amountInvestedUSDC,
                claimParams[i].takeNoCarry,
                claimParams[i].amountToClaim,
                price
            );
        }

        return carryAmounts;
    }

    /// @notice Setter for the generic registry.
    function setGenericRegistry(IGenericRegistry registry) external onlyRole(MANAGER_ROLE) {
        genericRegistry = registry;
    }

    /// @notice Setter for the platform carry BPS
    /// @dev We use a separate setter for the platform carry over setting it in the setCarryWithdrawerSettings
    /// as the platform is separate from a carry receiver.
    /// @param bps The platform's carry in basis points.
    function setPlatformCarryBPS(uint16 bps) external onlyRole(MANAGER_ROLE) {
        if (bps > 2000) {
            revert InvalidConfiguration("Platform carry BPS cannot be greater than 20%");
        }

        totalCarryBPS = totalCarryBPS - platformCarryBPS + bps;
        platformCarryBPS = bps;
    }

    /// @notice Updates the claimers of the distributor.
    /// @dev The function must be used with UTMOST CAUTION since it can change the user's and total amount invested, which will interfere with the claimable amount computation.
    /// @param claimers The claimer settings to update.
    /// @param expectedRoot The expected root of the user settings merkle tree.
    function setClaimers(Claimer[] calldata claimers, bytes32 expectedRoot) external onlyRole(MANAGER_ROLE) {
        _setClaimers(claimers, expectedRoot);
        // TODO add ConfigChanged event
    }

    /// @notice Internal function to set the user settings.
    /// @dev The merkle tree root of the settings is computed and compared against the expected root.
    /// This is intended as a sanity check to make sure we can correctly compute the merkle tree root on the backend.
    function _setClaimers(Claimer[] memory claimers, bytes32 expectedRoot) internal {
        uint64 totalAmountInvestedUSDC_ = 0;
        bytes32[] memory claimerLeaves = new bytes32[](claimers.length);
        for (uint256 i = 0; i < claimers.length; i++) {
            Claimer memory s = claimers[i];

            if (s.entityUUID == PLATFORM_ENTITY_UUID) {
                revert InvalidConfiguration("entityUUID cannot be the platform entityUUID");
            }

            if (s.signer == address(0)) {
                revert InvalidConfiguration("signer is zero");
            }

            if (s.amountInvestedUSDC == 0) {
                revert InvalidConfiguration("amount invested is zero");
            }

            // TODO check dupes somehow?

            totalAmountInvestedUSDC_ += s.amountInvestedUSDC;
            claimerLeaves[i] = Merkle.hashLeaf(abi.encode(s));
            // TODO add some guard rails (input expected totals), sanity checks, etc
        }
        totalAmountInvestedUSDC = totalAmountInvestedUSDC_;

        bytes32 computedRoot = Merkle.computeRootInPlace(claimerLeaves);
        if (computedRoot != expectedRoot) {
            revert UnexpectedClaimerMerkleRoot(claimerLeaves, computedRoot, expectedRoot);
        }
        claimersRoot = computedRoot;
    }

    /// @notice Updates the carry withdrawer settings.
    /// @dev This function must be used with UTMOST CAUTION since it can change the carry withdrawable amount, which will interfere with the carryWithdrawable computation.
    /// @param settings The carry withdrawer settings to update.
    function setCarryWithdrawerSettings(CarryWithdrawer[] calldata settings) external onlyRole(MANAGER_ROLE) {
        _setCarryWithdrawerSettings(settings);
        // TODO add ConfigChanged event?
    }

    /// @notice Internal function to set the carry withdrawer settings.
    /// @dev The merkle tree root of the settings is computed and compared against the expected root.
    /// This is intended as a sanity check to make sure we can correctly compute the merkle tree root on the backend.
    function _setCarryWithdrawerSettings(CarryWithdrawer[] memory settings) internal {
        // clearing the existing carry receivers first
        uint256 numExisting = _carryWithdrawerUUIDs.length;
        if (numExisting > 0) {
            for (uint256 i = 0; i < numExisting; i++) {
                delete _carryWithdrawers[_carryWithdrawerUUIDs[i]];
            }
            delete _carryWithdrawerUUIDs;
        }

        uint16 totalCarryBPS_ = 0;
        for (uint256 i = 0; i < settings.length; i++) {
            CarryWithdrawer memory s = settings[i];

            if (s.entityUUID == PLATFORM_ENTITY_UUID) {
                revert InvalidConfiguration("entityUUID cannot be the platform entityUUID");
            }

            if (s.signer == address(0)) {
                revert InvalidConfiguration("signer is zero");
            }

            if (s.carryBPS == 0) {
                revert InvalidConfiguration("carry BPS is zero");
            }

            if (_carryWithdrawers[s.entityUUID].signer != address(0)) {
                revert InvalidConfiguration("entityUUID already exists");
            }

            totalCarryBPS_ += s.carryBPS;
            _carryWithdrawerUUIDs.push(s.entityUUID);
            _carryWithdrawers[s.entityUUID] = CarryWithdrawerWithoutUUID({signer: s.signer, carryBPS: s.carryBPS});
            // TODO add some guard rails (input expected totals), sanity checks, etc
        }
        totalCarryBPS = totalCarryBPS_ + platformCarryBPS;
    }

    function setUnlocker(UnlockerLib.Unlocker calldata unlocker_) external onlyRole(ENG_MANAGER_ROLE) {
        UnlockerLib.validate(unlocker_);
        unlocker = unlocker_;
        emit ConfigChanged(this.setUnlocker.selector, "setUnlocker((address,bytes6,bytes6))", abi.encode(unlocker_));
    }

    function setForcedDistributionModeEnabled(bool enabled) external onlyRole(MANAGER_ROLE) {
        isForcedDistributionModeEnabled = enabled;
    }

    /// @notice Allows the manager to recover any tokens sent to the contract.
    /// @dev This is intended as a safeguard and should only be used in emergencies and with utmost care.
    function recoverTokens(IERC20 coin, address to, uint256 amount) external onlyRole(MANAGER_ROLE) {
        coin.safeTransfer(to, amount);
    }

    function carryWithdrawerUUIDs() external view returns (bytes16[] memory) {
        return _carryWithdrawerUUIDs;
    }

    function carryWithdrawer(bytes16[] calldata entityUUIDs)
        external
        view
        returns (CarryWithdrawerWithoutUUID[] memory)
    {
        CarryWithdrawerWithoutUUID[] memory ret = new CarryWithdrawerWithoutUUID[](entityUUIDs.length);
        for (uint256 i = 0; i < entityUUIDs.length; i++) {
            ret[i] = _carryWithdrawers[entityUUIDs[i]];
        }
        return ret;
    }

    /// @notice Sets whether token claims and carry withdrawals are enabled.
    function _setEnabled(bool isEnabled_) internal {
        isEnabled = isEnabled_;
        emit ConfigChanged(this.setEnabled.selector, "setEnabled(bool)", abi.encode(isEnabled_));
    }

    /// @notice Sets whether the deal funding is enabled.
    function setEnabled(bool isEnabled_) external onlyRole(ENG_MANAGER_ROLE) {
        _setEnabled(isEnabled_);
    }

    /// @notice Pauses the deal funding.
    /// @dev Equivalent to `setEnabled(false)`.
    function pause() external onlyRole(PAUSER_ROLE) {
        _setEnabled(false);
    }

    /// @notice Ensures that a function can only be called if a given flag is true.
    modifier onlyIf(bool flag) {
        if (!flag) {
            revert Disabled();
        }
        _;
    }
}
