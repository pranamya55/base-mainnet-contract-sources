// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// External: OpenZeppelin
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
// External: Uniswap V4 Core
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
// External: Uniswap V4 Periphery
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

// Internal
import {IHookPolicy} from "./interfaces/IHookPolicy.sol";
import {IMessageSender} from "./interfaces/IMessageSender.sol";

/// @title VerifiedPoolsBasicHook contract.
///
/// @notice A basic hook contract for `Verified Pools` that allows the pool to enforce
///         policies before and after a swap, add liquidity, remove liquidity, and donate.
///
/// @author Coinbase
/// @author Uniswap (https://github.com/Uniswap/v4-core)
contract VerifiedPoolsBasicHook is AccessControl, BaseHook, Pausable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;
    using SafeCast for int128;
    using StateLibrary for IPoolManager;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   STATE VARIABLES                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // 0xc9427259795fbc38fba3c2cee3d5b9149dbd8568750d94c8c1e55097205722a6
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("verifiedpools.basichook.feemanager");
    // 0xe53c482cb40ad90cfac9dc9d5aa54fd4e0437f8fb656379b0186088cb5d260ce
    bytes32 public constant PAUSER_ROLE = keccak256("verifiedpools.basichook.pauser");
    /// @notice The zero address.
    address public constant ZERO_ADDRESS = address(0);
    /// @notice A zero `PoolId` to represent the default pool. This is used for both policies and hook fees.
    PoolId public constant DEFAULT_POOL = PoolId.wrap(0);
    /// @notice The max possible fee charged for each swap in bips (10000bp = 100%).
    uint128 public constant TOTAL_FEE_BIPS = 10_000;
    /// @notice The maximum fee that can be charged for a swap in bips (100bp = 1%).
    uint128 public constant HOOK_FEE_CAP = 100;

    /// @notice The addresses that are allowed to initialize a pool using this hook.
    mapping(address initializer => bool allowed) public initializers;
    /// @notice The beforeSwap policy for a given pool.
    mapping(PoolId pool => address policy) public beforeSwapPolicies;
    /// @notice The beforeAddLiquidity policy for a given pool.
    mapping(PoolId pool => address policy) public beforeAddLiquidityPolicies;
    /// @notice The beforeRemoveLiquidity policy for a given pool.
    mapping(PoolId pool => address policy) public beforeRemoveLiquidityPolicies;
    /// @notice The beforeDonate policy for a given pool.
    mapping(PoolId pool => address policy) public beforeDonatePolicies;

    /// @notice The PositionManagerStatus for a given positionManager contract. Only trusted position managers can
    ///         invoke the beforeAddLiquidity and beforeRemoveLiquidity hooks. When a position manager is removed, it
    ///         is designated as REDUCE_ONLY to allow users to remove their liquidity or migrate to a new position
    ///         manager.
    mapping(address posm => PositionManagerStatus positionManagerStatus) public positionManagers;
    /// @notice The address of the trusted swap routers. Only trusted routers can
    ///         invoke the beforeSwap hook.
    mapping(address addr => bool allowed) public swapRouters;
    /// @notice The address of the trusted quoter contracts. These contracts must enforce that all quote functions explicitly revert.
    mapping(address addr => bool allowed) public quoters;
    /// @notice The address of the trusted Donate router. Only this router can invoke the beforeDonate hook.
    address public poolDonateRouter;

    /// @notice A struct describing whether fees are enabled for a hook, and the fee amount
    struct HookFeeConfiguration {
        /// @dev The configuration for whether hook fees are enabled for a given pool.
        bool enabled;
        /// @dev The fee charged for each swap in a given pool in bips (1bp = 0.01%).
        uint128 fee;
    }

    /// @notice The hook fee configuration for a given pool.
    mapping(PoolId pool => HookFeeConfiguration hookFeeConfiguration) internal hookFeeConfigurations;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EVENTS                                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an initializer address is allowed.
    ///
    /// @param addr The address allowed.
    event InitializerAllowed(address indexed addr);
    /// @notice Emitted when an initializer address is removed.
    ///
    /// @param addr The address removed.
    event InitializerRemoved(address indexed addr);
    /// @notice Emitted when the beforeAddLiquidity policy for a pool is updated.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeAddLiquidity hook policy for the pool.
    event BeforeAddLiquidityPolicyUpdated(PoolId indexed id, address indexed policy);
    /// @notice Emitted when the beforeRemoveLiquidity policy for a pool is updated.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeRemoveLiquidity hook policy for the pool.
    event BeforeRemoveLiquidityPolicyUpdated(PoolId indexed id, address indexed policy);
    /// @notice Emitted when the beforeSwap policy for a pool is updated.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeSwap hook policy for the pool.
    event BeforeSwapPolicyUpdated(PoolId indexed id, address indexed policy);
    /// @notice Emitted when the beforeDonate policy for a pool is updated.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeDonate hook policy for the pool.
    event BeforeDonatePolicyUpdated(PoolId indexed id, address indexed policy);
    /// @notice Emitted when the PoolModifyLiquidity router is updated.
    ///
    /// @param positionManager The address of the PositionManager.
    /// @param allowed Whether the position manager is allowed or not.
    event PositionManagerUpdated(address indexed positionManager, bool allowed);
    /// @notice Emitted when the PoolSwap router is updated.
    ///
    /// @param router The address of the PoolSwap router.
    /// @param allowed Whether the router is allowed to invoke the beforeSwap hook.
    event SwapRouterUpdated(address indexed router, bool allowed);
    /// @notice Emitted when the quoter is updated.
    ///
    /// @param quoter The address of the new quoter.
    /// @param allowed Whether the quoter is allowed to invoke the beforeSwap hook.
    event QuoterUpdated(address indexed quoter, bool allowed);
    /// @notice Emitted when the PoolDonate router is updated.
    ///
    /// @param router The address of the new PoolDonate router.
    event PoolDonateRouterUpdated(address indexed router);
    /// @notice Emitted when the hook fee is enabled or disabled.
    ///
    /// @param id The pool id.
    /// @param enabled The new enabled flag for the hook fee.
    event FeeToggled(PoolId indexed id, bool enabled);
    /// @notice Emitted when the hook fee is updated.
    ///
    /// @param id The pool id.
    /// @param fee The new hook fee for the pool.
    event FeeUpdated(PoolId indexed id, uint256 fee);
    /// @notice Emitted when fees are withdrawn.
    ///
    /// @param recipient The address to receive the fees.
    /// @param currency The currency to withdraw the fees for.
    /// @param amount The amount of fees withdrawn.
    event FeesWithdrawn(address indexed recipient, Currency indexed currency, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   ERRORS                                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when an address is invalid.
    ///
    /// @param addr The invalid address.
    error InvalidAddress(address addr);
    /// @notice Emitted when an initializer address is not allowed.
    ///
    /// @param addr The address not allowed.
    error InitializerNotAllowed(address addr);
    /// @notice Emitted when the hook policy is invalid.
    error InvalidPolicy();
    /// @notice Emitted when the router is invalid.
    error InvalidRouter();
    /// @notice Emitted when the PositionManager is invalid.
    error InvalidPositionManager();
    /// @notice Emitted when the router is not allowed.
    ///
    /// @param router The address of the router.
    error RouterNotAllowed(address router);
    /// @notice Emitted when the PositionManager is not allowed.
    ///
    /// @param positionManager The address of the PositionManager.
    error PositionManagerNotAllowed(address positionManager);
    /// @notice Emitted when the caller is not authorized.
    ///
    /// @param caller The address of the caller.
    error Unauthorized(address caller);
    /// @notice Emitted when the hook fee exceeds the fee cap.
    ///
    /// @param fee The fee that exceeds the cap.
    error FeeExceedsCap(uint256 fee);
    /// @notice Emitted when the sender address does not pass the policy check.
    ///
    /// @param sender The sender address.
    error PolicyCheckFailed(address sender);

    /// @notice The status for a position manager contract
    enum PositionManagerStatus {
        /// @dev These contracts cannot be used to manage positions (the default value)
        FORBIDDEN,
        /// @dev These contracts can be used for all liquidity operations.
        ALLOWED,
        /// @dev These contracts can only be used to reduce or close a liquidity position.
        REDUCE_ONLY
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   CONSTRUCTOR                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @param poolManager_ The Uniswap V4 pool manager.
    /// @param defaultAdmin The address of the default admin.
    /// @param defaultFeeManager The address of the default fee manager.
    /// @param defaultPauser The address of the default pauser.
    /// @param beforeAddLiquidityPolicy The default beforeAddLiquidity hook policy.
    /// @param beforeRemoveLiquidityPolicy The default beforeRemoveLiquidity hook policy.
    /// @param beforeSwapPolicy The default beforeSwap hook policy.
    /// @param beforeDonatePolicy The default beforeDonate hook policy.
    /// @param positionManager The address of the PositionManager that is trusted to modify liquidity.
    /// @param poolSwapRouter The address of the PoolSwap router that is trusted to perform swaps.
    /// @param poolDonateRouter_ The address of the PoolDonate router that is trusted to perform donate.
    /// @param quoter_ The Uniswap V4 Quoter contract that is trusted to simulate swaps.
    constructor(
        IPoolManager poolManager_,
        address defaultAdmin,
        address defaultFeeManager,
        address defaultPauser,
        IHookPolicy beforeAddLiquidityPolicy,
        IHookPolicy beforeRemoveLiquidityPolicy,
        IHookPolicy beforeSwapPolicy,
        IHookPolicy beforeDonatePolicy,
        address positionManager,
        address poolSwapRouter,
        address poolDonateRouter_,
        address quoter_
    ) BaseHook(poolManager_) {
        if (defaultAdmin == ZERO_ADDRESS) {
            revert InvalidAddress(defaultAdmin);
        }
        if (defaultFeeManager == ZERO_ADDRESS) {
            revert InvalidAddress(defaultFeeManager);
        }
        if (defaultPauser == ZERO_ADDRESS) {
            revert InvalidAddress(defaultPauser);
        }

        _allowInitializer(defaultAdmin);

        _setBeforeAddLiquidityPolicy(DEFAULT_POOL, beforeAddLiquidityPolicy);
        _setBeforeRemoveLiquidityPolicy(DEFAULT_POOL, beforeRemoveLiquidityPolicy);
        _setBeforeSwapPolicy(DEFAULT_POOL, beforeSwapPolicy);
        _setBeforeDonatePolicy(DEFAULT_POOL, beforeDonatePolicy);

        _setPositionManager(positionManager, true);
        _setSwapRouter(poolSwapRouter, true);
        _setQuoter(quoter_, true);
        _setPoolDonateRouter(poolDonateRouter_);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(FEE_MANAGER_ROLE, defaultFeeManager);
        _grantRole(PAUSER_ROLE, defaultPauser);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   EXTERNAL FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IHooks
    ///
    /// @notice Checks if the `sender` is allowed to initialize a pool.
    function beforeInitialize(address sender, PoolKey calldata, uint160)
        external
        virtual
        override
        whenNotPaused
        returns (bytes4)
    {
        if (sender == ZERO_ADDRESS || !initializers[sender]) {
            revert InitializerNotAllowed(sender);
        }

        return this.beforeInitialize.selector;
    }

    /// @inheritdoc IHooks
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override onlyPoolManager whenNotPaused returns (bytes4) {
        if (sender == ZERO_ADDRESS || positionManagers[sender] != PositionManagerStatus.ALLOWED) {
            revert PositionManagerNotAllowed(sender);
        }

        PoolId id = key.toId();
        IHookPolicy policy = IHookPolicy(beforeAddLiquidityPolicies[DEFAULT_POOL]);
        if (beforeAddLiquidityPolicies[id] != ZERO_ADDRESS) {
            policy = IHookPolicy(beforeAddLiquidityPolicies[id]);
        }

        // Ensure that the sender is verified by the policy, reverting if the sender is not verified.
        _ensureSenderVerified(sender, policy, hookData);

        return BaseHook.beforeAddLiquidity.selector;
    }

    /// @inheritdoc IHooks
    ///
    /// @notice Checks if the `sender` is allowed to remove liquidity by
    ///         verifying against the RemoveLiquidityPolicy.
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata hookData
    ) external view override onlyPoolManager whenNotPaused returns (bytes4) {
        if (sender == ZERO_ADDRESS || positionManagers[sender] == PositionManagerStatus.FORBIDDEN) {
            revert PositionManagerNotAllowed(sender);
        }

        PoolId id = key.toId();
        IHookPolicy policy = IHookPolicy(beforeRemoveLiquidityPolicies[DEFAULT_POOL]);
        if (beforeRemoveLiquidityPolicies[id] != ZERO_ADDRESS) {
            policy = IHookPolicy(beforeRemoveLiquidityPolicies[id]);
        }

        // Ensure that the sender is verified by the policy, reverting if the sender is not verified.
        _ensureSenderVerified(sender, policy, hookData);

        return BaseHook.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc IHooks
    function beforeSwap(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        view
        override
        onlyPoolManager
        whenNotPaused
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Skip policy checks if we are coming from an approved Quoter.
        if (quoters[sender]) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        if (sender == ZERO_ADDRESS || !swapRouters[sender]) {
            revert RouterNotAllowed(sender);
        }

        PoolId id = key.toId();
        IHookPolicy policy = IHookPolicy(beforeSwapPolicies[DEFAULT_POOL]);
        if (beforeSwapPolicies[id] != ZERO_ADDRESS) {
            policy = IHookPolicy(beforeSwapPolicies[id]);
        }

        // Ensure that the sender is verified by the policy, reverting if the sender is not verified.
        _ensureSenderVerified(sender, policy, hookData);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @inheritdoc IHooks
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager whenNotPaused returns (bytes4, int128) {
        PoolId id = key.toId();
        HookFeeConfiguration memory hookFeeConfiguration = hookFeeConfigurations[id];

        // Check for hookFee intent
        if (!hookFeeConfiguration.enabled) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Retrieve the hook fee for the pool
        uint128 hookFee =
            hookFeeConfiguration.fee == 0 ? hookFeeConfigurations[DEFAULT_POOL].fee : hookFeeConfiguration.fee;
        if (hookFee == 0) {
            return (BaseHook.afterSwap.selector, 0);
        }

        // Take a fee from the unspecified
        // zeroForOne + amount < 0 -> amount0 is specified, amount1 is unspecified
        // zeroForOne + amount > 0 -> amount1 is specified, amount0 is unspecified
        // oneForZero + amount < 0 -> amount1 is specified, amount0 is unspecified
        // oneForZero + amount > 0 -> amount0 is specified, amount1 is unspecified
        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());
        // if fee is on output, get the absolute output amount
        if (swapAmount < 0) swapAmount = -swapAmount;

        uint256 feeAmount = uint256(uint128(swapAmount)) * hookFee / TOTAL_FEE_BIPS;
        poolManager.mint(address(this), feeCurrency.toId(), feeAmount);

        return (BaseHook.afterSwap.selector, feeAmount.toInt128());
    }

    /// @inheritdoc IHooks
    function beforeDonate(address sender, PoolKey calldata key, uint256, uint256, bytes calldata hookData)
        external
        virtual
        override
        onlyPoolManager
        whenNotPaused
        returns (bytes4)
    {
        if (sender == ZERO_ADDRESS || sender != poolDonateRouter) {
            revert RouterNotAllowed(sender);
        }

        PoolId id = key.toId();
        IHookPolicy policy = IHookPolicy(beforeDonatePolicies[DEFAULT_POOL]);
        if (beforeDonatePolicies[id] != ZERO_ADDRESS) {
            policy = IHookPolicy(beforeDonatePolicies[id]);
        }

        // Ensure that the sender is verified by the policy, reverting if the sender is not verified.
        _ensureSenderVerified(sender, policy, hookData);

        return BaseHook.beforeDonate.selector;
    }

    /// @notice Allows the hook owner to withdraw all fees collected by the hook for a currency.
    /// @notice This function can only be called by the Fee Manager.
    /// @notice This function is not callable when the contract is paused.
    ///
    /// @param recipient The address to receive the fees.
    /// @param currency The currency to withdraw the fees for.
    ///
    /// @return amount The amount of fees withdrawn.
    function withdrawFees(address recipient, Currency currency)
        external
        onlyRole(FEE_MANAGER_ROLE)
        whenNotPaused
        returns (uint256 amount)
    {
        if (recipient == ZERO_ADDRESS) {
            revert InvalidAddress(recipient);
        }

        // Unlock on the hook and fire the handleWithdrawFee callback.
        // The callback will handle the actual fee withdrawal and transfer the fees to the recipient.
        amount =
            abi.decode(poolManager.unlock(abi.encodeCall(this.handleWithdrawFee, (recipient, currency))), (uint256));

        emit FeesWithdrawn(recipient, currency, amount);
    }

    /// @notice A callback method to handle fee withdrawal once unlocked.
    ///
    /// @param recipient The address to receive the fees.
    /// @param currency The currency to withdraw the fees for.
    ///
    /// @return amount The amount of fees withdrawn
    function handleWithdrawFee(address recipient, Currency currency) external returns (uint256 amount) {
        // Prevent any other contract from triggering this callback
        if (msg.sender != address(this)) {
            revert Unauthorized(msg.sender);
        }

        amount = poolManager.balanceOf(address(this), currency.toId());
        if (amount == 0) {
            return 0;
        }

        poolManager.burn(address(this), currency.toId(), amount);
        poolManager.take(currency, recipient, amount);
    }

    /// @notice Enables or disables the hook fee for a specific pool.
    /// @notice This function can only be called by the Fee Manager.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @dev It is not possible to enable/disable hook fees for all pools by calling this function on `DEFAULT_POOL`.
    ///      The hook fees for each pool must be enabled and disabled individually.
    ///
    /// @param id The pool id.
    /// @param enabled The hookFee enabled flag for this pool.
    function setHookFeeEnabled(PoolId id, bool enabled) external onlyRole(FEE_MANAGER_ROLE) {
        _validatePool(id);
        if (hookFeeConfigurations[id].enabled == enabled) {
            return;
        }

        hookFeeConfigurations[id].enabled = enabled;
        emit FeeToggled(id, enabled);
    }

    /// @notice Sets the `hookFee` for a pool.
    /// @notice This function can only be called by the Fee Manager.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @dev Setting the hookFee for the `DEFAULT_POOL` will only result in fees for pools if they have had fees
    ///      enabled by calling `setHookFeesEnabled`.
    /// @dev Setting the hookFee value to `0` for a specific pool will cause that pool to use the fee value of the
    ///      `DEFAULT_POOL`. If a fee of `0` is desired, instead call `setHookFeeEnabled(id, false)`.
    ///
    /// @param id The pool id.
    /// @param hookFee The new hook fee in bips, e.g. 100 = 1%.
    function setHookFee(PoolId id, uint128 hookFee) external onlyRole(FEE_MANAGER_ROLE) {
        _validatePool(id);
        if (hookFee > HOOK_FEE_CAP) {
            revert FeeExceedsCap(hookFee);
        }
        if (hookFeeConfigurations[id].fee == hookFee) {
            return;
        }

        hookFeeConfigurations[id].fee = hookFee;
        emit FeeUpdated(id, hookFee);
    }

    /// @notice Adds a new `initializer` address.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param initializer The `initializer` address to be added to allowlist.
    function allowInitializer(address initializer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _allowInitializer(initializer);
    }

    /// @notice Removes an `initializer` address.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param initializer The `initializer` address to be removed from allowlist.
    function removeInitializer(address initializer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeInitializer(initializer);
    }

    /// @notice Sets the default `policy` or `policy` override for the beforeAddLiquidity hook.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeAddLiquidity hook policy for the pool.
    function setBeforeAddLiquidityPolicy(PoolId id, IHookPolicy policy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBeforeAddLiquidityPolicy(id, policy);
    }

    /// @notice Sets the default `policy` or `policy` override for the beforeRemoveLiquidity hook.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeRemoveLiquidity hook policy for the pool.
    function setBeforeRemoveLiquidityPolicy(PoolId id, IHookPolicy policy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBeforeRemoveLiquidityPolicy(id, policy);
    }

    /// @notice Sets the default `policy` or `policy` override for the beforeSwap hook.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeSwap hook policy for the pool.
    function setBeforeSwapPolicy(PoolId id, IHookPolicy policy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBeforeSwapPolicy(id, policy);
    }

    /// @notice Sets the default `policy` or `policy` override for the befreDonate hook.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param id The pool id.
    /// @param policy The new beforeDonate hook policy for the pool.
    function setBeforeDonatePolicy(PoolId id, IHookPolicy policy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setBeforeDonatePolicy(id, policy);
    }

    /// @notice Sets the Quoter address.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param quoter_ The address of the Quoter contract.
    /// @param allowed Whether the quoter is allowed to invoke the beforeSwap hook.
    function setQuoter(address quoter_, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setQuoter(quoter_, allowed);
    }

    /// @notice Sets the PoolDonate `router`.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param router The address of the PoolDonate router.
    function setPoolDonateRouter(address router) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPoolDonateRouter(router);
    }

    /// @notice Set whether the `positionManager` address is allowed to perform liquidity operations.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param positionManager The address of the PositionManager.
    /// @param allowed Whether the PositionManager is allowed to modify liquidity.
    function setPositionManager(address positionManager, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setPositionManager(positionManager, allowed);
    }

    /// @notice Set whether the `router` address is allowed to invoke the beforeSwap hook.
    /// @notice This function can only be called by the admin.
    /// @notice This function is callable when the contract is paused.
    ///
    /// @param router The address of the PoolSwap router or qouter whose access need to be updated.
    /// @param allowed Whether the router is allowed to invoke the beforeSwap hook.
    function setSwapRouter(address router, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setSwapRouter(router, allowed);
    }

    /// @notice Pause the hooks contract in case of emergency
    /// @notice This function can only be called by the pauser.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause the hooks contract
    /// @notice This function can only be called by the pauser.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PUBLIC FUNCTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Returns the supported hook callbacks.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: true,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Returns the hookFee for a pool (in bips).
    function hookFees(PoolId pool) public view returns (uint128) {
        return hookFeeConfigurations[pool].fee;
    }

    /// @notice Returns whether hook fees are enabled for a pool.
    function hookFeesEnabled(PoolId pool) public view returns (bool) {
        return hookFeeConfigurations[pool].enabled;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   INTERNAL FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Internal function to add a new `initializer` address.
    /// @dev It may emit an {InitializerAllowed} event.
    ///
    /// @param initializer The address to be added to allowlist.
    function _allowInitializer(address initializer) internal {
        if (initializer == ZERO_ADDRESS) {
            revert InvalidAddress(initializer);
        }
        if (initializers[initializer]) {
            return;
        }

        initializers[initializer] = true;
        emit InitializerAllowed(initializer);
    }

    /// @dev Internal function to remove an `initializer` address.
    /// @dev It may emit an {InitializerRemoved} event.
    ///
    /// @param initializer The address to be removed from allowlist.
    function _removeInitializer(address initializer) internal {
        if (initializer == ZERO_ADDRESS) {
            revert InvalidAddress(initializer);
        }
        if (initializers[initializer] == false) {
            return;
        }

        initializers[initializer] = false;
        emit InitializerRemoved(initializer);
    }

    /// @dev Internal function to set the default `policy` or the `policy` override for the beforeAddLiquidity.
    /// @dev It may emit a {BeforeAddLiquidityPolicyUpdated} event.
    ///
    /// @param id The pool id
    /// @param policy The new beforeAddLiquidity hook policy for the pool.
    function _setBeforeAddLiquidityPolicy(PoolId id, IHookPolicy policy) internal {
        _validatePoolAndPolicy(id, policy);
        if (beforeAddLiquidityPolicies[id] == address(policy)) {
            return;
        }

        beforeAddLiquidityPolicies[id] = address(policy);
        emit BeforeAddLiquidityPolicyUpdated(id, address(policy));
    }

    /// @dev Internal function to set the default `policy` or the `policy` override for the beforeRemoveLiquidity.
    /// @dev It may emit a {BeforeRemoveLiquidityPolicyUpdated} event.
    ///
    /// @param id The pool id
    /// @param policy The new beforeRemoveLiquidity hook policy for the pool.
    function _setBeforeRemoveLiquidityPolicy(PoolId id, IHookPolicy policy) internal {
        _validatePoolAndPolicy(id, policy);
        if (beforeRemoveLiquidityPolicies[id] == address(policy)) {
            return;
        }

        beforeRemoveLiquidityPolicies[id] = address(policy);
        emit BeforeRemoveLiquidityPolicyUpdated(id, address(policy));
    }

    /// @dev Internal function to set the default policy or the policy override for the beforeSwap.
    /// @dev It may emit a {BeforeSwapPolicyUpdated} event.
    ///
    /// @param id The pool id
    /// @param policy The new beforeSwap hook policy for the pool.
    function _setBeforeSwapPolicy(PoolId id, IHookPolicy policy) internal {
        _validatePoolAndPolicy(id, policy);
        if (beforeSwapPolicies[id] == address(policy)) {
            return;
        }

        beforeSwapPolicies[id] = address(policy);
        emit BeforeSwapPolicyUpdated(id, address(policy));
    }

    /// @dev Internal function to set the default policy or the policy override for the beforeDonate.
    /// @dev It may emit a {BeforeDonatePolicyUpdated} event.
    ///
    /// @param id The pool id
    /// @param policy The new beforeDonate hook policy for the pool.
    function _setBeforeDonatePolicy(PoolId id, IHookPolicy policy) internal {
        _validatePoolAndPolicy(id, policy);
        if (beforeDonatePolicies[id] == address(policy)) {
            return;
        }

        beforeDonatePolicies[id] = address(policy);
        emit BeforeDonatePolicyUpdated(id, address(policy));
    }

    /// @dev Internal function to set if the `positionManager` address is allowed to
    ///      perform liquidity operations.
    /// @dev It may emit a {PositionManagerUpdated} event.
    ///
    /// @param positionManager The address of the PositionManager.
    /// @param allowed Whether the PositionManager is allowed to modify liquidity.
    function _setPositionManager(address positionManager, bool allowed) internal {
        if (positionManager == ZERO_ADDRESS) {
            revert InvalidPositionManager();
        }
        if ((positionManagers[positionManager] == PositionManagerStatus.ALLOWED) ? allowed : !allowed) {
            return;
        }
        positionManagers[positionManager] = allowed ? PositionManagerStatus.ALLOWED : PositionManagerStatus.REDUCE_ONLY;
        emit PositionManagerUpdated(positionManager, allowed);
    }

    /// @notice Internal function to set the PoolSwap `router`.
    /// @notice It may emit a {SwapRouterUpdated} event.
    ///
    /// @param router The address of the PoolSwap router.
    /// @param allowed Whether the router is allowed to invoke the beforeSwap hook.
    function _setSwapRouter(address router, bool allowed) internal {
        if (router == ZERO_ADDRESS) {
            revert InvalidRouter();
        }
        if (swapRouters[router] == allowed) {
            return;
        }
        swapRouters[router] = allowed;
        emit SwapRouterUpdated(router, allowed);
    }

    /// @dev Internal function to set the quoter.
    /// @dev It may emit a {QuoterUpdated} event.
    ///
    /// @param quoterAddress The address of the quoter contract.
    /// @param allowed Whether the quoter is allowed to invoke the beforeSwap hook.
    function _setQuoter(address quoterAddress, bool allowed) internal {
        if (quoterAddress == ZERO_ADDRESS) {
            revert InvalidAddress(quoterAddress);
        }
        if (quoters[quoterAddress] == allowed) {
            return;
        }
        quoters[quoterAddress] = allowed;
        emit QuoterUpdated(quoterAddress, allowed);
    }

    /// @dev Internal function to set the PoolDonate `router`.
    /// @dev It may emit a {PoolDonateRouterUpdated} event.
    ///
    /// @param router The address of the PoolDonate router.
    function _setPoolDonateRouter(address router) internal {
        if (router == ZERO_ADDRESS) {
            revert InvalidRouter();
        }
        if (router == poolDonateRouter) {
            return;
        }
        poolDonateRouter = router;
        emit PoolDonateRouterUpdated(router);
    }

    /// @dev Internal function to get the originalSender within an action and verifies that sender against a policy.
    ///      This function permits a nested call from a PositionManager or Router into another PositionManager or
    ///      Router as long as both contracts are allowlisted and follow the `IMessageSender` interface.
    /// @dev This function reverts if the sender is not verified by the policy
    ///
    /// @param sender The initial msg.sender to the PoolManager
    /// @param policy The specific policy for this action
    /// @param policyData Any additional data to pass to the policy contract
    function _ensureSenderVerified(address sender, IHookPolicy policy, bytes calldata policyData) internal view {
        address originalSender = IMessageSender(sender).msgSender();
        if (policy.verify(originalSender, policyData)) {
            // In the hot path, a user directly interacts with the Router or PositionManager contract. We have
            // verified the sender, and so can return early.
            return;
        }
        if (swapRouters[originalSender] || (positionManagers[originalSender] != PositionManagerStatus.FORBIDDEN)) {
            // In this case `originalSender` is not a verified user. Instead, it is an allowed contract and the user
            // that interacted with this contract can be obtained by calling its `msgSender` function.
            // This user can then be verified against the policy.
            address routerSender = IMessageSender(originalSender).msgSender();
            if (policy.verify(routerSender, policyData)) {
                return;
            }
            revert PolicyCheckFailed(routerSender);
        }
        revert PolicyCheckFailed(originalSender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   PRIVATE FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Validates the pool and `policy` before setting the hook policy.
    ///
    /// @param id The pool id.
    /// @param policy The hook policy.
    function _validatePoolAndPolicy(PoolId id, IHookPolicy policy) private view {
        _validatePool(id);
        _validatePolicy(policy);
    }

    /// @dev Validates the `policy` to ensure non-zero.
    ///
    /// @param policy The hook policy.
    function _validatePolicy(IHookPolicy policy) private pure {
        if (address(policy) == ZERO_ADDRESS) {
            revert InvalidPolicy();
        }
    }

    /// @dev Validates the pool is initialized when it is not the default.
    ///
    /// @param id The pool id.
    function _validatePool(PoolId id) private view {
        if (!_isDefaultPool(id) && !_isPoolInitialized(id)) {
            revert IPoolManager.PoolNotInitialized();
        }
    }

    /// @dev Checks if the pool `id` is the default pool.
    ///
    /// @param id The pool id.
    ///
    /// @return Whether the pool is the default pool.
    function _isDefaultPool(PoolId id) private pure returns (bool) {
        return PoolId.unwrap(id) == PoolId.unwrap(DEFAULT_POOL);
    }

    /// @dev Checks if the pool is initialized using the pool `id`.
    ///
    /// @param id The pool id.
    ///
    /// @return Whether the pool is initialized.
    function _isPoolInitialized(PoolId id) private view returns (bool) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        return sqrtPriceX96 != 0;
    }
}
